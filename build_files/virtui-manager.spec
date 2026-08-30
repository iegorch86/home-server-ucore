%global debug_package %{nil}

Name:           virtui-manager
Version:        %{virtui_version}
Release:        1%{?dist}
Summary:        Terminal-based interface for managing libvirt virtual machines

License:        GPL-3.0-or-later
URL:            https://github.com/aginies/virtui-manager
Source0:        virtui-manager-payload.tar.gz

BuildArch:      noarch

# The application and its private Textual copy live under /usr/libexec.
# Runtime dependencies provided by Fedora are listed explicitly below.
AutoReqProv:    no

Requires:       bash
Requires:       python3
Requires:       python3-libvirt
Requires:       python3-pyyaml
Requires:       python3-requests
Requires:       python3-netifaces
Requires:       python3-gobject
Requires:       python3-packaging
Requires:       python3-markdown-it-py
Requires:       libosinfo
Requires:       osinfo-db
Requires:       tmux
Requires:       7zip
Requires:       novnc
Requires:       python3-websockify


%description
VirtUI Manager is a terminal-based interface for managing QEMU/KVM
virtual machines through libvirt.

This package is built specifically for the Home Server uCore HCI image.
Its Python application and private Textual dependency are isolated under
/usr/libexec/virtui-manager.


%prep


%build


%install
mkdir -p %{buildroot}

tar -xzf %{SOURCE0} -C %{buildroot}

mkdir -p %{buildroot}%{_bindir}

cat > %{buildroot}%{_bindir}/virtui-manager <<'EOF'
#!/usr/bin/bash

export PYTHONPATH="/usr/libexec/virtui-manager/python${PYTHONPATH:+:${PYTHONPATH}}"

exec /usr/bin/python3 -c \
    'from vmanager.wrapper import main; main()' \
    "$@"
EOF

chmod 0755 %{buildroot}%{_bindir}/virtui-manager


cat > %{buildroot}%{_bindir}/vmc <<'EOF'
#!/usr/bin/bash

export PYTHONPATH="/usr/libexec/virtui-manager/python${PYTHONPATH:+:${PYTHONPATH}}"

exec /usr/bin/python3 -c \
    'from vmanager.wrapper import cmd_main; cmd_main()' \
    "$@"
EOF

chmod 0755 %{buildroot}%{_bindir}/vmc

ln -s vmc %{buildroot}%{_bindir}/virtui-manager-cmd


%files
%license %{_datadir}/licenses/virtui-manager/LICENSE

%{_bindir}/virtui-manager
%{_bindir}/virtui-manager-cmd
%{_bindir}/vmc

%{_libexecdir}/virtui-manager/


%changelog
* Sun Aug 30 2026 Home Server uCore <noreply@localhost> - 3.3.1-1
- Initial Home Server uCore HCI package
