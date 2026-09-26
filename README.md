# Maqueta CDG - Obligatorio Seguridad en Redes y Datos

Santiago Cardozo [309364] Claudio Lorenzo [250576]

---

## 1. Requisitos

En el host Windows:

- VirtualBox (sin Extension Pack)
- Vagrant
- WSL con Debian, para el repositorio, Ansible Vault y GPG

En WSL:

- git, gnupg, ansible-core
- La coleccion community.general (`ansible-galaxy collection install community.general`), ansible-core no la trae y los roles la usan
- La clave privada GPG del integrante
- Un par de claves ssh para entrar a las vms (distinto del que usamos para github)

ISO a descargar

- OPNsense

---

## 2. Estructura
# 2.1 Generalidades

- El repositorio se edita en WSL
- Vagrant corre en Windows, desde su propio directorio
- Ansible se corre desde WSL, no hay maquina orquestadora dentro de la maqueta

Para pasar los archivos al directorio de Vagrant sin que Windows les meta .txt:

```bash
cp vagrant/{Vagrantfile,config.yaml} /mnt/c/<directorio-vagrant>/
```

---

# 2.2 Como funciona GPG

Las contrasenas (root de cada host, sudo de la cuenta de automatizacion, credenciales
de servicios) van cifradas en el repositorio con Ansible Vault. La contrasena de vault se guarda mediante GPG

```contrasenas -> cifradas con Ansible Vault en el repo
contrasena de Vault -> cifrada con GPG para los dos (en el repo, vault-pass.gpg)
clave privada GPG -> en el WSL de cada uno de nosotros, protegida con una frase que pusimos```

Asi nada queda en texto plano. Lo unico que tenemos que recordar es la frase de GPG. La contrasena de Vault nadie la sabe, es aleatoria y solo existe
cifrada.

**Configuracion por primera vez**

En WSL, cada uno:

```bash
sudo apt install -y gnupg pinentry-curses
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc && source ~/.bashrc

gpg --quick-generate-key "Nombre Apellido <correo>" future-default default 1y
gpg --armor --export <correo> > gpg/nombre-apellido.asc
```

La clave publica .asc se commitea la privada no.

**Crear la contrasena de Vault**

Importar la clave publica del otro integrante y:

```bash
gpg --import gpg/integrante.asc

openssl rand -base64 32 | gpg --encrypt --armor --trust-model always \
  -r correo1 -r correo2 \
  -o ansible/vault-pass.gpg
```

**Editar o ver secretos:**

```bash
cd ansible
ansible-vault edit inventory/host_vars/srv01/vault.yml
ansible-vault view inventory/host_vars/srv01/vault.yml
```

El script `vault-pass.sh` descifra `vault-pass.gpg` y le entrega el resultado a Ansible. Pide la frase de GPG en lugar de la del vault. Va configurado en ansible.cfg:

```ini
vault_password_file = vault-pass.sh
```

Como ansible corre en el mismo WSL donde esta la clave privada GPG, el descifrado es
transparente y no hay que pegar nada a mano

**De momento los playbooks no piden contrasena. Pendiente configurarlo**

**Si clonas el repo**

El vault-pass.gpg del repo esta cifrado para nuestras claves, no vas a poder
descifrarlo. Tampoco los archivos vault.yml. Hay que empezar de cero:

1. Generar tu clave GPG
2. Borrar ansible/vault-pass.gpg y generar uno nuevo cifrado para tu clave
3. Borrar los inventory/host_vars/*/vault.yml, no se pueden recuperar
4. Volver a crear los secretos que hagan falta con ansible-vault

---

## 3. Instalacion OPNsense

Se hace por fuera de vagrant porque no tiene box oficial

1. Crear la VM en VirtualBox nombre rtr01
2. Adaptadores 1 a 4 desde la GUI:
   - 1: NAT
   - 2: Internal Network, nombre `dmz`
   - 3: Internal Network, nombre `app`
   - 4: Internal Network, nombre `soc`
3. El quinto adaptador por consola, porque la gui de virtualbox solo muestra cuatro.

```
VBoxManage modifyvm "rtr01" --nic5 hostonly --hostonlyadapter5 "VirtualBox Host-Only Ethernet Adapter #2"
```

4. Cargar la ISO, cambiar la contrasena de root
5. Asignar interfaces:
   - WAN: `em0`
   - LAN: `em4`
   - OPT1: `em1` (dmz), OPT2: `em2` (app), OPT3: `em3` (soc)
6. Setear las ip a cada interfaz. Van sin dhcp, sin gateway y sin ipv6:
   - LAN 10.10.10.254/24
   - OPT1 10.10.40.254/24
   - OPT2 10.10.30.254/24
   - OPT3 10.10.20.254/24
   
   La WAN no se toca queda en dhcp
8. Entrar al router con `https://10.10.10.254` con usuario root y configurar:
   - System > Settings > General: zona horaria America/Montevideo
   - Services > Network Time: habilitado, interfaces LAN, OPT1, OPT2, OPT3 (WAN no)
   - Firewall > NAT > Outbound: verificar que este en modo automatico
   - Firewall > Aliases: crear NET_MGMT, NET_SOC, NET_APP, NET_DMZ, NET_MAQUETA, los SRV_* y los PORTS_*
   - Firewall > Rules: en OPT1, OPT2 y OPT3, las tres reglas NTP, salida web y DNS
9. Recargar los alias con Firewall > Aliases > Actions > Update
10. Guardar un backup del router en `firewall/opnsense/`

**Ojo con el punto 8**: las tres reglas van en las TRES interfaces. Si a alguna zona le
falta la de salida web o la de DNS, los hosts de esa zona no bajan paquetes y el error
aparece en apt, no en el router. Ya nos paso con OPT1 y OPT3 despues de restaurar un backup

---

## 4. Levantar las maquinas

Primero, la clave publica del admin tiene que estar en el directorio de vagrant, el
Vagrantfile la lee de ahi y la instala en todas las vms:

```bash
cp ~/.ssh/id_ansible.pub /mnt/c/<directorio-vagrant>/files/admin.pub
```

Desde el directorio de Vagrant en Windows:

```
vagrant status
vagrant up
```

Levanta las 9 vms e instala la clave publica del admin en todas. Las vms quedan sin
hardenizar, eso lo hace ansible despues

---

## 5. Configurar con Ansible

Desde WSL, en la carpeta ansible del repo:

La primera vez o despues de recrear maquinas, hay que indicar el puerto 22: las vms
nuevas todavia no tienen el puerto 7664 (elegido por nosotros) configurado

```bash
ansible-playbook playbooks/01-hardening-base.yml -e ansible_port=22
```

De ahi en mas, sin el `-e`:

```bash
ansible-playbook playbooks/01-hardening-base.yml
```

Antes de correr los playbooks conviene chequear que todas las zonas tengan salida, sino
el error salta despues en apt y cuesta encontrarlo:

```bash
ansible all -m shell -a "timeout 5 getent hosts deb.debian.org >/dev/null && echo OK || echo SIN-SALIDA"
```

Verificar:

```bash
ansible all -m ping
ansible all -a "ip route get 1.1.1.1"     # sale por su gateway .254
ansible all -a "chronyc sources"          # sincroniza contra .254
```

Verificar auditd:

```bash
ansible all -a "auditctl -s" -b | grep enabled
ansible all -m shell -a "auditctl -l | wc -l" -b
```

Idempotencia: correr el playbook dos veces seguidas, la segunda tiene que dar changed=0
en las 9 maquinas. Esa salida va a docs/evidencias/

---

## 6. no olvidarse

- **Maquina recreada**: hay que borrar su entrada de `known_hosts` en WSL, sino SSH
  aborta la sesion por cambio de clave de host:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R <ip>
```

- **Handlers de Ansible**: si una tarea falla, los handlers pendientes se descartan y el
  servicio queda con la configuracion vieja
- **Secretos**: nada de contrasenas en el repositorio sin cifrar
- **Actualizaciones automaticas desactivadas**: el rol base deshabilita
  unattended-upgrades. Los hosts no se parchean solos, hay que hacerlo
  con Ansible
- **auditd desde el arranque**: el rol cambia los parametros de grub pero toma efecto
  recien despues de reiniciar el host
- **rtr01 primero**: es lo primero que se prende y lo ultimo que se apaga. Sin el las vms
  no tienen salida ni hora. Y nunca guardar su estado, siempre apagado completo, sino
  vuelve con la hora vieja y se la pasa a todas
- **Backup del router**: cada vez que se toca una regla o un alias, exportar y commitear

---

## 7. Orden de los roles

1. `base` - hora, ruta por defecto, resolucion de nombres **(quitar resolucion de nombres cuando pongamos el server dns)**
2. `firewall_nftables` - firewall local
3. `ssh_hardening` - endurecimiento de SSH
4. `auditd` - auditoria del sistema con reglas mapeadas a MITRE ATT&CK

Si se aplica el firewall antes que base, el host queda aislado: la ruta todavia apunta
al NAT y el firewall bloquea esa interfaz.

---

## 8. ubicacion de cada cosa

```
ansible/          playbooks, roles e inventario
docs/adr/         decisiones de arquitectura y por que se tomaron
docs/evidencias/  salidas de comandos que respaldan el informe
firewall/opnsense/ backup de la configuracion del firewall
vagrant/          Vagrantfile y config.yaml
gpg/              claves publicas nuestras
```
