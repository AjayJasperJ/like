import 'package:flutter/material.dart';

import '../../../core/utils/validators.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({
    required this.submitLabel,
    required this.onSubmit,
    this.collectName = false,
    super.key,
  });

  final String submitLabel;
  final bool collectName;
  final Future<void> Function(String name, String email, String password)
      onSubmit;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _key,
        child: Column(
          children: [
            if (widget.collectName) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  final requiredError =
                      Validators.requiredText(value, label: 'Name');
                  if (requiredError != null) return requiredError;
                  return value!.trim().length < 2
                      ? 'Name must contain at least 2 characters'
                      : null;
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
              validator: Validators.password,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      );

  void _submit() {
    if (_key.currentState?.validate() != true) return;
    widget.onSubmit(_name.text, _email.text, _password.text);
  }
}
