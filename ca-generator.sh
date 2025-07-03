#!/bin/bash

# Absolute path
BASE_DIR="$(pwd)"
CA_DIR="$BASE_DIR/CA"

echo "Creating directories for CA in: $CA_DIR"
mkdir -p "$CA_DIR"/{certs,crl,newcerts,private,csr}
chmod 700 "$CA_DIR/private"
touch "$CA_DIR/index.txt"
echo 1000 > "$CA_DIR/serial"

CA_KEY="$CA_DIR/private/ca.key"
CA_CERT="$CA_DIR/certs/ca.crt"
OPENSSL_CNF="$CA_DIR/openssl.cnf"

echo "Generating OpenSSL configuration file..."
cat > "$OPENSSL_CNF" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CA_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
private_key       = \$dir/private/ca.key
certificate       = \$dir/certs/ca.crt

default_days      = 825
default_md        = sha256
policy            = policy_loose
email_in_dn       = no
name_opt          = ca_default
cert_opt          = ca_default
copy_extensions   = copy
unique_subject    = no

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
CN = Elyerr.org Root CA

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
EOF

# Insert alt names from $ALT_NAMES or defaults
if [ -n "$ALT_NAMES" ]; then
  IFS=',' read -ra DNS_ARRAY <<< "$ALT_NAMES"
  i=1
  for dns in "${DNS_ARRAY[@]}"; do
    echo "DNS.$i = $dns" >> "$OPENSSL_CNF"
    ((i++))
  done
else
  echo "DNS.1 = elyerr.xyz" >> "$OPENSSL_CNF"
  echo "DNS.2 = *.elyerr.xyz" >> "$OPENSSL_CNF"
fi

echo "Generating private key for CA..."
openssl genrsa -out "$CA_KEY" 4096
chmod 400 "$CA_KEY"

echo "Generating self-signed certificate for CA..."
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
    -out "$CA_CERT" \
    -config "$OPENSSL_CNF"

chmod 444 "$CA_CERT"

echo "Generating certificate issuer script..."
cat > "$BASE_DIR/issue-cert.sh" <<EOF
#!/bin/bash

DOMAIN=\$1
if [ -z "\$DOMAIN" ]; then
  echo "Usage: ./issue-cert.sh <domain>"
  exit 1
fi

CA_DIR="$CA_DIR"
OPENSSL_CNF="$OPENSSL_CNF"
KEY="\$CA_DIR/private/\$DOMAIN.key"
CSR="\$CA_DIR/csr/\$DOMAIN.csr"
CRT="\$CA_DIR/certs/\$DOMAIN.crt"

# Generate private key
openssl genrsa -out "\$KEY" 2048

# Create CSR
openssl req -new -key "\$KEY" -out "\$CSR" -subj "/CN=\$DOMAIN"

# Sign CSR with CA
openssl ca -batch -config "\$OPENSSL_CNF" \
    -extensions v3_req \
    -days 825 \
    -notext \
    -in "\$CSR" \
    -out "\$CRT"

echo -e "\\n  Certificate generated for: \$DOMAIN"
echo "Key: \$KEY"
echo "Cert: \$CRT"
EOF

chmod +x "$BASE_DIR/issue-cert.sh"

echo -e "\nCA successfully created at: $CA_DIR"
echo "To issue a certificate: ./issue-cert.sh <your.domain>"
