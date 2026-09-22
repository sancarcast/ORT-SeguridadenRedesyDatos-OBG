#!/bin/sh
# Descifra la contrasena de Ansible Vault desde vault-pass.gpg
exec gpg --quiet --batch --decrypt "$(dirname "$0")/vault-pass.gpg" 2>/dev/null
