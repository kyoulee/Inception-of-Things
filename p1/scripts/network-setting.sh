#!/bin/bash

# network dns setting
cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

if grep -q "^#\?DNSSEC=" /etc/systemd/resolved.conf; then
    sed -i 's/^#\?DNSSEC=.*/DNSSEC=no/' /etc/systemd/resolved.conf
else
    sed -i '/^\[Resolve\]/a DNSSEC=no' /etc/systemd/resolved.conf
fi

systemctl restart systemd-resolved