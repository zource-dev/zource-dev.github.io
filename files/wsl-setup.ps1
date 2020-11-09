Invoke-Expression "$env:UserProfile\AppData\Local\Microsoft\WindowsApps\ubuntu2004.exe run exit"
$distro="ubuntu-20.04"
wsl --set-default $distro

$username = Invoke-Expression "wsl whoami"

$wslSetup = @'
#!/bin/sh
export DEBIAN_FRONTEND=noninteractive > /dev/null

echo 'Adding packages source...'
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list > /dev/null

echo 'Updating packages information...'
sudo apt-get update > /dev/null
sudo apt-get remove -yqq --ignore-missing cmdtest nodejs yarn jq  > /dev/null

echo 'Upgrading packages...'
sudo apt-get dist-upgrade -yqq > /dev/null

echo 'Installing utilities...'

sudo apt-get install -yqq daemonize dbus-user-session yarn jq build-essential apt-transport-https ca-certificates wget curl gnupg-agent software-properties-common > /dev/null

echo 'Installing Node.JS...'
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash > /dev/null

echo 'Configuring systemd...'
cat <<- "EOF" | sudo tee -a /usr/sbin/start-systemd-namespace > /dev/null
#!/bin/bash

SYSTEMD_PID=$(ps -ef | grep '/lib/systemd/systemd --system-unit=basic.target$' | grep -v unshare | awk '{print $2}')
if [ -z "$SYSTEMD_PID" ] || [ "$SYSTEMD_PID" != "1" ]; then
    export PRE_NAMESPACE_PATH="$PATH"
    (set -o posix; set) | \
        grep -v "^BASH" | \
        grep -v "^DIRSTACK=" | \
        grep -v "^EUID=" | \
        grep -v "^GROUPS=" | \
        grep -v "^HOME=" | \
        grep -v "^HOSTNAME=" | \
        grep -v "^HOSTTYPE=" | \
        grep -v "^IFS='.*"$'\n'"'" | \
        grep -v "^LANG=" | \
        grep -v "^LOGNAME=" | \
        grep -v "^MACHTYPE=" | \
        grep -v "^NAME=" | \
        grep -v "^OPTERR=" | \
        grep -v "^OPTIND=" | \
        grep -v "^OSTYPE=" | \
        grep -v "^PIPESTATUS=" | \
        grep -v "^POSIXLY_CORRECT=" | \
        grep -v "^PPID=" | \
        grep -v "^PS1=" | \
        grep -v "^PS4=" | \
        grep -v "^SHELL=" | \
        grep -v "^SHELLOPTS=" | \
        grep -v "^SHLVL=" | \
        grep -v "^SYSTEMD_PID=" | \
        grep -v "^UID=" | \
        grep -v "^USER=" | \
        grep -v "^_=" | \
        cat - > "$HOME/.systemd-env"
    echo "PATH='$PATH'" >> "$HOME/.systemd-env"
    exec sudo /usr/sbin/enter-systemd-namespace "$BASH_EXECUTION_STRING"
fi
if [ -n "$PRE_NAMESPACE_PATH" ]; then
    export PATH="$PRE_NAMESPACE_PATH"
fi
EOF
sudo chmod +x /usr/sbin/start-systemd-namespace

cat <<- "EOF" | sudo tee -a /usr/sbin/enter-systemd-namespace > /dev/null
#!/bin/bash

if [ "$UID" != 0 ]; then
    echo "You need to run $0 through sudo"
    exit 1
fi

SYSTEMD_PID="$(ps -ef | grep '/lib/systemd/systemd --system-unit=basic.target$' | grep -v unshare | awk '{print $2}')"
if [ -z "$SYSTEMD_PID" ]; then
    while [ -z "$SYSTEMD_PID" ]; do
        SYSTEMD_PID="$(ps -ef | grep '/lib/systemd/systemd --system-unit=basic.target$' | grep -v unshare | awk '{print $2}')"
    done
fi

if [ -n "$SYSTEMD_PID" ] && [ "$SYSTEMD_PID" != "1" ]; then
    if [ -n "$1" ] && [ "$1" != "bash --login" ] && [ "$1" != "/bin/bash --login" ]; then
        exec /usr/bin/nsenter -t "$SYSTEMD_PID" -a \
            /usr/bin/sudo -H -u "$SUDO_USER" \
            /bin/bash -c 'set -a; source "$HOME/.systemd-env"; set +a; exec bash -c '"$(printf "%q" "$@")"
    else
        exec /usr/bin/nsenter -t "$SYSTEMD_PID" -a \
            /bin/login -p -f "$SUDO_USER" \
            $(/bin/cat "$HOME/.systemd-env" | grep -v "^PATH=")
    fi
    echo "Existential crisis"
fi
EOF

sudo sed -i 9a"$(which daemonize) /usr/bin/unshare --fork --pid --mount-proc /lib/systemd/systemd --system-unit=basic.target" /usr/sbin/enter-systemd-namespace
sudo chmod +x /usr/sbin/enter-systemd-namespace

cat <<- "EOF" | sudo tee -a /etc/sudoers.d/wsl > /dev/null
Defaults        env_keep += WSLPATH
Defaults        env_keep += WSLENV
Defaults        env_keep += WSL_INTEROP
Defaults        env_keep += WSL_DISTRO_NAME
Defaults        env_keep += PRE_NAMESPACE_PATH
%sudo ALL=(ALL) NOPASSWD: /usr/sbin/enter-systemd-namespace
EOF

sudo sed -i 2a"# Start or enter a PID namespace in WSL2\nsource /usr/sbin/start-systemd-namespace\n" /etc/bash.bashrc

sudo touch /root/.systemd-env

echo 'Configuring display...'

cat <<- "EOF" | tee -a ~/.bashrc > /dev/null
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
export DISPLAY=$(cat /etc/resolv.conf | grep -Po "(?<=nameserver\s)([\d.]+)"):0
export LIBGL_ALWAYS_INDIRECT=1
export PULSE_SERVER=tcp:$(cat /etc/resolv.conf | grep -Po "(?<=nameserver\s)([\d.]+)")
EOF

rm ~/setup.sh
'@

$wslSetup | wsl bash -c "tr -d '\015' > ~/setup.sh && chmod +x ~/setup.sh"
wsl ~/setup.sh

Write-Host 'Restarting Ubuntu...'
wsl --terminate $distro
do {
  Write-Host 'Checking restart progress...'
  Start-Sleep 1
} while((wsl -l -q --running) -contains $distro);

cmd.exe /C setx WSLENV BASH_ENV/u
cmd.exe /C setx BASH_ENV /etc/bash.bashrc
