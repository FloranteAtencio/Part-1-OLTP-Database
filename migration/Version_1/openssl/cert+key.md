# 1. Generate CA Private Key
openssl genrsa -out ca.key 4096

# 2. Generate CA Certificate (Valid for 10 years)
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=PostgreSQL CA"

# 3. Generate Server Private Key
openssl genrsa -out server.key 4096

# 4. Generate Server Certificate Signing Request (CSR)
openssl req -new -key server.key -out server.csr \
  -subj "/CN=dbhost.yourdomain.com"

# 5. Sign the Server Certificate with the CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365 -sha256

# 6. Secure Permissions
chmod 600 server.key
chown postgres:postgres server.key server.crt ca.crt   