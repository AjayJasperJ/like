"""Syntax-tree API extraction. Signatures are source text, never reconstructed bodies."""
import html
from pathlib import Path
import re
import textwrap

from tree_sitter import Language, Parser
import tree_sitter_dart

PARSER = Parser(Language(tree_sitter_dart.language()))
DECLARATIONS = {'class_definition', 'mixin_declaration', 'enum_declaration',
                'extension_declaration', 'type_alias', 'function_signature'}


def content(node, data):
    return data[node.start_byte:node.end_byte].decode()


def descendants(node, types):
    for child in node.named_children:
        if child.type in types:
            yield child
        else:
            yield from descendants(child, types)


def documentation(comments):
    lines = []
    for comment in comments:
        text = re.sub(r'^\s*/// ?', '', comment, flags=re.M)
        if comment.lstrip().startswith('/**'):
            text = re.sub(r'^\s*/\*\*?|\*/\s*$', '', text)
            text = re.sub(r'^\s*\* ?', '', text, flags=re.M)
        # Source examples remain available without introducing h1s in the reference.
        text = re.sub(r'^#{1,6}\s+(.+)$', r'**\1**', text, flags=re.M)
        lines.append(text)
    return '\n'.join(lines).strip()


def node_name(node, data):
    if 'constructor_signature' in node.type:
        return '.'.join(content(c, data) for c in node.named_children if c.type == 'identifier')
    named = node.child_by_field_name('name')
    if named:
        return content(named, data)
    if node.type == 'type_alias':
        return content(next(c for c in node.named_children if c.type in ('type_identifier', 'identifier')), data)
    if node.type in ('constant_constructor_signature', 'constructor_signature', 'factory_constructor_signature'):
        identifiers = [content(c, data) for c in node.named_children if c.type == 'identifier']
        return '.'.join(identifiers)
    if node.type == 'operator_signature':
        params = next((c for c in node.named_children if c.type == 'formal_parameter_list'), None)
        return re.sub(r'^.*\boperator\s*', 'operator ', content(node, data)[:params.start_byte - node.start_byte] if params else content(node, data)).strip()
    return ''


def field_records(node, data, docs, include_private=False):
    listing = next((c for c in node.named_children if c.type == 'initialized_identifier_list'), None)
    if not listing:
        listing = next((c for c in node.named_children if c.type == 'static_final_declaration_list'), None)
    if not listing:
        return []
    prefix = content(node, data)[:listing.start_byte - node.start_byte].strip()
    field_type = re.sub(r'^(?:(?:static|late|final|const|var|external|covariant)\s*)+', '', prefix).strip() or 'inferred (see initializer)'
    records = []
    for item in listing.named_children:
        if item.type not in ('initialized_identifier', 'static_final_declaration'):
            continue
        name_node = item.child_by_field_name('name') or next((c for c in item.named_children if c.type == 'identifier'), None)
        if not name_node:
            continue
        name = content(name_node, data)
        if name.startswith('_') and not include_private:
            continue
        text = content(item, data)
        default = text[len(name):].lstrip()
        default = default.removeprefix('=').strip() if default.startswith('=') else None
        records.append({'name': name, 'type': field_type, 'signature': prefix + ' ' + name + ';',
                        'default': default, 'description': docs, 'kind': 'field', 'parameters': [],
                        'line': item.start_point.row + 1})
    return records


def parameter_records(signature, data, fields):
    params = next(descendants(signature, {'formal_parameter_list'}), None)
    if params is None:
        return []
    out = []

    def group(container, named=False, optional=False):
        segment = []
        for child in container.children:
            if child.type == 'optional_formal_parameters':
                group(child, named=content(child, data).lstrip().startswith('{'), optional=True)
                continue
            if child.type in ('(', ')', '{', '}', '[', ']'):
                continue
            if child.type == ',':
                emit(segment, named, optional)
                segment = []
            else:
                segment.append(child)
        emit(segment, named, optional)

    def emit(nodes, named, optional):
        formal = next((n for n in nodes if n.type == 'formal_parameter'), None)
        if formal is None:
            return
        raw = data[nodes[0].start_byte:nodes[-1].end_byte].decode().strip()
        text = content(formal, data)
        name_node = formal.child_by_field_name('name')
        forwarded = next((c for c in formal.named_children if c.type in ('constructor_param', 'super_formal_parameter')), None)
        if forwarded:
            ids = [c for c in forwarded.named_children if c.type == 'identifier']
            name = content(ids[-1], data) if ids else ''
            param_type = fields.get(name, {}).get('type', 'inherited; see superclass')
            if named and forwarded.type == 'constructor_param':
                name = name.lstrip('_')  # Dart 3.12 public name for private initializing formal
        else:
            name = content(name_node, data) if name_node else ''
            param_type = text[:name_node.start_byte - formal.start_byte].strip() if name_node else text
            param_type = re.sub(r'^covariant\s+', '', param_type) or 'dynamic / inferred'
        required = not optional or bool(re.search(r'\brequired\b', raw[:raw.find(text) + 1])) or raw.startswith('required ')
        # Defaults are sibling expression nodes. This avoids splitting callback/default map commas.
        equals = next((i for i, n in enumerate(nodes) if n.type == '='), None)
        default = data[nodes[equals + 1].start_byte:nodes[-1].end_byte].decode().strip() if equals is not None else None
        out.append({'name': name, 'type': param_type, 'kind': 'named' if named else 'positional',
                    'required': required, 'default': default, 'signature': raw,
                    'description': fields.get(name, {}).get('description', '') if forwarded else ''})

    group(params)
    return out


def callable_record(node, data, fields, docs):
    sig = node
    if node.type in ('declaration', 'method_signature'):
        sig = next((c for c in node.named_children if c.type.endswith('_signature')), None)
        if sig is None:
            return None
    name = node_name(sig, data)
    constructor = 'constructor_signature' in sig.type
    if not name or (name.split('.')[-1].startswith('_') and not name.startswith('operator ')):
        return None
    kind = 'constructor' if constructor else {'getter_signature': 'getter', 'setter_signature': 'setter'}.get(sig.type, 'method')
    # Keep modifiers (static/factory) from the wrapper but omit initializer/body implementation.
    end = sig.end_byte
    start = node.start_byte
    text = data[start:end].decode().strip().rstrip(';') + ';'
    return {'name': name, 'kind': kind, 'signature': textwrap.dedent(text),
            'description': docs, 'parameters': parameter_records(sig, data, fields),
            'line': node.start_point.row + 1}


def parse_library(source, path):
    data = source.encode()
    tree = PARSER.parse(data)
    if tree.root_node.has_error:
        raise ValueError('Dart syntax extraction failed: ' + path)
    records, comments = [], []
    for node in tree.root_node.named_children:
        if node.type == 'documentation_comment':
            comments.append(content(node, data))
            continue
        if node.type in ('annotation', 'comment'):
            continue
        docs = documentation(comments)
        comments = []
        if node.type not in DECLARATIONS:
            continue
        name = node_name(node, data)
        if not name or name.startswith('_'):
            continue
        body = node.child_by_field_name('body')
        if body is None:
            body = next((c for c in node.named_children if c.type in ('class_body', 'enum_body', 'extension_body', 'mixin_body')), None)
        if node.type == 'function_signature':
            record = callable_record(node, data, {}, docs)
            record.update({'kind': 'function', 'source': path, 'members': []})
            records.append(record)
            continue
        if node.type == 'type_alias':
            records.append({'name': name, 'kind': 'typedef', 'signature': content(node, data),
                            'description': docs, 'members': [], 'source': path, 'line': node.start_point.row + 1})
            continue
        if body is None:
            raise ValueError('Unsupported declaration body: ' + path + ':' + name)
        fields, members, pending = {}, [], []
        for member in body.named_children:
            if member.type == 'documentation_comment':
                pending.append(content(member, data))
                continue
            if member.type in ('annotation', 'comment'):
                continue
            description = documentation(pending)
            pending = []
            if member.type == 'declaration':
                for field in field_records(member, data, description, include_private=True):
                    fields[field['name']] = field
            if member.type == 'enum_constant':
                constant = node_name(member, data)
                if not constant.startswith('_'):
                    members.append({'name': constant, 'kind': 'enum value', 'signature': content(member, data),
                                    'description': description, 'parameters': [], 'line': member.start_point.row + 1})
        pending = []
        for member in body.named_children:
            if member.type == 'documentation_comment':
                pending.append(content(member, data))
                continue
            if member.type in ('annotation', 'comment'):
                continue
            description = documentation(pending)
            pending = []
            if member.type in ('method_signature', 'declaration'):
                record = callable_record(member, data, fields, description)
                if record:
                    members.append(record)
        members.extend(field for field in fields.values() if not field['name'].startswith('_'))
        kind = {'class_definition': 'class', 'mixin_declaration': 'mixin', 'enum_declaration': 'enum', 'extension_declaration': 'extension'}[node.type]
        header = data[node.start_byte:body.start_byte].decode().strip()
        constructor_types = {'constructor_signature', 'constant_constructor_signature', 'factory_constructor_signature'}
        has_constructor = any(any(descendants(member, constructor_types)) for member in body.named_children if member.type in ('declaration', 'method_signature'))
        if kind == 'class' and not has_constructor and not re.search(r'\babstract\b', header):
            members.insert(0, {'name': name, 'kind': 'constructor', 'signature': name + '();',
                'description': 'Implicit unnamed Dart constructor (no constructor is explicitly declared in this class).',
                'parameters': [], 'line': node.start_point.row + 1, 'implicit': True})
        records.append({'name': name, 'kind': kind, 'signature': header, 'description': docs,
                        'members': members, 'source': path, 'line': node.start_point.row + 1,
                        'widget': bool(re.search(r'extends\s+(?:StatefulWidget|StatelessWidget)', header))})
    return records


def exported_api(root):
    root = Path(root).resolve()
    cache = {}
    external = set()

    def exports(path, stack=()):
        if path in stack:
            return {}
        source = (root / path).read_text()
        local = {r['name']: r for r in cache.setdefault(path, parse_library(source, path))}
        for statement in re.findall(r"\bexport\s+('[^']+'[^;]*);", source, re.S):
            uri = re.match(r"'([^']+)'", statement)[1]
            shows = re.findall(r'\bshow\s+([^;]+?)(?=\bhide\b|$)', statement)
            hides = re.findall(r'\bhide\s+([^;]+?)(?=\bshow\b|$)', statement)
            include = set(re.findall(r'\b\w+\b', ' '.join(shows))) if shows else None
            exclude = set(re.findall(r'\b\w+\b', ' '.join(hides)))
            if uri.startswith('package:'):
                external.add((uri, tuple(sorted(include or [])), tuple(sorted(exclude))))
                continue
            target = (root / path).parent.joinpath(uri).resolve()
            if not target.is_relative_to(root):
                raise ValueError('Export outside repository: ' + uri)
            child = exports(target.relative_to(root).as_posix(), stack + (path,))
            local.update({name: item for name, item in child.items() if (include is None or name in include) and name not in exclude})
        return local

    core = exports('lib/like.dart')
    testing = exports('lib/testing.dart')
    records = []
    for name, value in sorted({**core, **testing}.items(), key=lambda x: (not x[1].get('widget', False), x[0].lower())):
        item = dict(value)
        item['entrypoints'] = (["package:like/like.dart"] if name in core else []) + (["package:like/testing.dart"] if name in testing else [])
        records.append(item)
    return {'symbols': records, 'external_exports': [{'library': x[0], 'show': list(x[1]), 'hide': list(x[2])} for x in sorted(external)]}


def cell(value):
    return html.escape(str(value)).replace('|', '&#124;').replace('\n', '<br>')


def render_reference(root, ref, repo):
    api = exported_api(root)
    lines = ['# Public API source index', '',
             'Read constructors, method signatures, parameters, callbacks, fields and defaults directly here.',
             'Generated from the Dart syntax tree and the actual `like.dart` / `testing.dart` export graph.', '',
             f'**{len(api["symbols"])} public package declarations**. Private names are omitted; `show`/`hide` export rules are respected.', '',
             'Signatures and comments describe this source revision. Inherited Flutter/framework members are not duplicated;',
             'super parameters without a local field type are labelled inherited. Parameter tables use public Dart 3.12 names for private initializing formals.',
             'Effective defaults computed inside constructor logic',
             'are not guessed. Source comments/examples may require application-owned types and handlers.', '',
             '[Download structured API JSON](api-reference.json) · [Read this page as Markdown](markdown/api.md)', '',
             '<label for="api-filter" class="api-filter-label">Filter widgets, classes and methods</label>',
             '<input id="api-filter" type="search" placeholder="Try LikeBuilder, slowInternet, get or cancelToken" autocomplete="off">',
             '<p id="api-filter-status" role="status">All public declarations shown. Expand a declaration to read its members.</p>', '',
             '## Widgets', '']
    widgets = [s for s in api['symbols'] if s.get('widget')]
    for item in widgets:
        lines.append(f'- [{item["name"]}](#{item["name"].lower()})')
    lines += ['', '## All declarations', '']
    for item in api['symbols']:
        name = item['name']
        url = f'{repo}/blob/{ref}/{item["source"]}#L{item["line"]}'
        lines += [f'<section class="api-symbol" data-api-symbol="{html.escape(name)}" markdown="1">',
                  f'### {name}', '', f'**{item["kind"]}** · ' + ('Widget · ' if item.get('widget') else '') + f'[Source]({url}) · [Type JSON](api-data/{name.lower()}.json)', '',
                  'Import: `' + ('package:like/like.dart' if 'package:like/like.dart' in item['entrypoints'] else 'package:like/testing.dart') + '`.', '',
                  '<details markdown="1">', f'<summary>Read {name} constructors, members and parameters</summary>', '',
                  '```dart', item['signature'], '```', '', item['description'], '']
        members = item.get('members', [])
        if item['kind'] == 'function':
            members = [item]
        if not members and item['kind'] == 'class':
            lines += ['No explicitly declared public members. Check Dart implicit constructor and superclass behavior.', '']
        for member in sorted(members, key=lambda m: ({'constructor': 0, 'method': 1, 'getter': 2, 'setter': 2, 'field': 3}.get(m['kind'], 4), m['line'])):
            lines += [f'#### {name}.{member["name"]}' if member['kind'] not in ('constructor', 'function') else f'#### {member["name"]}', '',
                      f'**{member["kind"]}**', '', '```dart', member['signature'], '```', '', member['description'], '']
            if member.get('default') is not None:
                lines += ['Initializer: `' + member['default'].replace('`', '') + '`.', '']
            params = member.get('parameters', [])
            if params:
                lines += ['| Parameter | Type / callback | Passing | Required | Explicit default |', '| --- | --- | --- | --- | --- |']
                for p in params:
                    lines.append('| ' + ' | '.join(cell(v) for v in [p['name'], p['type'], p['kind'], 'yes' if p['required'] else 'no', p['default'] if p['default'] is not None else '—']) + ' |')
                lines.append('')
                for p in params:
                    if p['description']:
                        lines += ['**' + p['name'] + '**', '', p['description'], '']
        lines += ['</details>', '</section>', '']
    lines += ['## Third-party re-exports', '', 'These types are exposed from dependencies; their inherited implementation belongs to those packages.', '']
    for item in api['external_exports']:
        lines.append('- `' + item['library'] + '`' + (' — show `' + '`, `'.join(item['show']) + '`' if item['show'] else '') + '.')
    return '\n'.join(lines), api
