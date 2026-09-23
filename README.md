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
- La clave privada GPG del integrante

ISO a descargar

- OPNsense

---

## 2. Estructura
# 2.1 Generalidades

- El repositorio se edita en WSL
- Vagrant corre en Windows, desde su propio directorio

La carpeta `claves/` nunca va al repositorio solo esta en el host windows

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
ansible-vault edit inventory/host_vars/srv01/vault.yml --vault-password-file vault-pass.sh
ansible-vault view inventory/host_vars/srv01/vault.yml --vault-password-file vault-pass.sh
```

El script `vault-pass.sh` descifra `vault-pass.gpg` y le entrega el resultado a Ansible. Pide la frase de GPG en lugar de la del vault

**Correr playbooks que usan secretos en ctrl01:**

ctrl01 NO tiene claves GPG porque es una maquina descartable y no debe guardar
secretos. Entonces la contrasena se descifra en WSL y se pega:

```bash
# en WSL
gpg -d ansible/vault-pass.gpg | clip.exe

# en ctrl01
ansible-playbook playbooks/XX.yml --ask-vault-pass
```

**De momento los playbooks no piden contrasena. Pendiente configurarlo**

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

---

## 4. Levantar las maquinas

Desde el directorio de Vagrant en Windows:

```
vagrant status
```

La primera vez genera las claves del nodo de control en `claves/`. Hay que cargar `claves/ctrl01_deploy.pub` en GitHub > el repo > Settings > Deploy keys

```
vagrant up
```

Levanta las 10 vms, instala la clave publica de ctrl01 en todas, y en ctrl01 ademas
instala las herramientas, configura SSH para GitHub y clona el repo

---

## 5. Configurar con Ansible

Desde ctrl01:

La primera vez o despues de recrear maquinas, hay que indicar el puerto 22: las vms
nuevas todavia no tienen el puerto 7664 (elegido por nosotros) configurado

```bash
ansible-playbook playbooks/01-hardening-base.yml -e ansible_port=22
```

De ahi en mas, sin el `-e`:

```bash
ansible-playbook playbooks/01-hardening-base.yml
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

---

## 6. no olvidarse

- **Maquina recreada**: hay que borrar su entrada de `known_hosts` en ctrl01, sino SSH
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
firewall/opnsense/ backup de la configuracion del firewall
vagrant/          Vagrantfile y config.yaml
gpg/              claves publicas nuestras
```
