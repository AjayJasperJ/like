"""Contract smoke test. Never prints credentials, response bodies or tokens."""
import json
from urllib.request import Request, urlopen

def call(path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = Request('https://dummyjson.com' + path,
                      data=None if body is None else json.dumps(body).encode(),
                      headers=headers)
    with urlopen(request, timeout=30) as response:
        assert response.status in (200, 201)
        return json.load(response)

products = call('/products?limit=2&skip=0')
assert len(products['products']) == 2 and products['total'] > 0
item = products['products'][0]
assert call('/products/' + str(item['id']))['id'] == item['id']
search = call('/products/search?q=phone&limit=2')
assert isinstance(search['products'], list)
login = call('/auth/login', {'username': 'emilys', 'password': 'emilyspass', 'expiresInMins': 30})
assert call('/auth/me', token=login['accessToken'])['id'] == login['id']
refresh = call('/auth/refresh', {'refreshToken': login['refreshToken'], 'expiresInMins': 30})
assert call('/auth/me', token=refresh['accessToken'])['id'] == login['id']
cart = call('/carts/add', {'userId': login['id'], 'products': [{'id': item['id'], 'quantity': 2}]}, login['accessToken'])
assert isinstance(cart['id'], int) and cart['totalQuantity'] == 2
print('PASS: public catalog, search, detail, login, profile, refresh and simulated checkout contracts')
