#!/bin/sh
# Ruta por defecto hacia el gateway de zona.

# Se ejecuta cada vez que una interfaz de red sube. Es necesario porque
# Vagrant reconfigura las interfaces despues del arranque, lo que elimina
# las rutas asociadas a ellas

[ "$IFACE" = "lo" ] && exit 0

# Solo instala la ruta si el gateway ya es alcanzable, es decir, si la
# interfaz de la zona correspondiente esta configurada

ip route get {{ base_gateway }} >/dev/null 2>&1 || exit 0

ip route replace default via {{ base_gateway }}
exit 0
