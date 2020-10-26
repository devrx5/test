client_number=$1
client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$client_number"p)
cd /etc/openvpn/server/easy-rsa/
./easyrsa --batch revoke "$client"
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
rm -f /etc/openvpn/server/crl.pem
cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
chown nobody:"$group_name" /etc/openvpn/server/crl.pem
