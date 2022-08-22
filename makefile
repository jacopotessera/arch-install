.PHONY: check-cfg print-cfg cfg partition chroot datetime locale user grub system fstab yay libvirt sway app all vm

ARCH_INSTALL := arch-install
VERSION := 0.1

MAKEFILE_JUSTNAME := $(firstword $(MAKEFILE_LIST))
MAKEFILE_COMPLETE := $(CURDIR)/$(MAKEFILE_JUSTNAME)

CONFIGURATION_JUSTNAME := $(ARCH_INSTALL_CONFIGURATION)
CONFIGURATION_COMPLETE := $(CURDIR)/$(CONFIGURATION_JUSTNAME)

DISK := $(ARCH_INSTALL_DISK)
P := $(ARCH_INSTALL_P)

HOSTNAME := $(ARCH_INSTALL_HOSTNAME)
USER := $(ARCH_INSTALL_USER)

PACMAN := pacman -Sy --noconfirm
YAY := sudo -u $(USER) yay -Sy --noconfirm

check-cfg:
ifeq ($(CONFIGURATION_JUSTNAME),)
	@echo "Run 'source configure.{fish,sh}'"
	@exit 1
endif	

print-cfg:
	@echo -e 'ARCH INSTALL CONFIGURATION:'
	@echo -e '\tMAKEFILE: $(MAKEFILE_COMPLETE)'
	@echo -e '\tCONFIGURATION FILE: $(CONFIGURATION_COMPLETE)'
	@echo -e '\tDISK: $(DISK)'
	@echo -e '\tP: $(P)'
	@echo -e '\tHOSTNAME: $(HOSTNAME)'
	@echo -e '\tUSER: $(USER)'

cfg: check-cfg print-cfg

partition: cfg
	parted /dev/$(DISK) mklabel gpt
	parted /dev/$(DISK) mkpart fat32 1M 512M
	parted /dev/$(DISK) mkpart ext4 512M 100%
	mkfs.fat -F 32 -n boot /dev/$(DISK)$(P)1
	mkfs.ext4 /dev/$(DISK)$(P)2 

partition-bios: cfg
	parted /dev/$(DISK) mklabel msdos
	parted /dev/$(DISK) mktable msdos
	parted /dev/$(DISK) mkpart ext4 1M 100%
	mkfs.ext4 /dev/$(DISK)$(P)1

mount:
	mount /dev/$(DISK)$(P)2 /mnt
	mkdir -p /mnt/boot
	mount /dev/$(DISK)$(P)1 /mnt/boot

mount-bios:
	mount /dev/$(DISK)$(P)1 /mnt

pacstrap:
	pacstrap /mnt base base-devel linux linux-firmware
	genfstab -U /mnt >> /mnt/etc/fstab

chroot:
	cp makefile /mnt/makefile
	cp $(CONFIGURATION_COMPLETE) /mnt/configure.sh
	cp -r ~/$(ARCH_INSTALL) /mnt/
	mkdir -p /mnt/var/lib/iwd
	-cp /var/lib/iwd/*.psk /mnt/var/lib/iwd/
	mkdir -p /mnt/home/$(USER)/.config/sway
	-cp config/sway/* /mnt/home/$(USER)/.config/sway
	mkdir -p /mnt/home/$(USER)/.ssh/
	-cp ~/.ssh/* /mnt/home/$(USER)/.ssh
	mkdir -p /mnt/etc
	cp etc/* /mnt/etc/
	mkdir -p /mnt/home/$(USER)/.config/fish
	cp config/fish/* /mnt/home/$(USER)/.config/fish
	arch-chroot /mnt

prepare: partition mount pacstrap chroot

prepare-bios: partition-bios mount-bios pacstrap chroot

all: cfg datetime locale user autologin grub system audio fstab yay libvirt sway app spotify

vm: cfg datetime locale user autologin grub system audio system_vm yay i3 app idea

vault: cfg datetime locale user grub-bios system system_vm

headless: cfg datetime locale user grub system system_vm

datetime:
	ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
	$(PACMAN) ntp
	ntpd -gq
	hwclock --systohc

locale:
	sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
	locale-gen

user: cfg
	$(PACMAN) sudo neovim fish
	useradd -m $(USER) -s /bin/fish
	usermod -a -G wheel,video,input $(USER)
	echo "$(USER):$(USER)" | chpasswd
	ln -s /usr/bin/nvim /usr/bin/vi
	ln -s /usr/bin/nvim /usr/bin/vim
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
	chown -R $(USER):$(USER) /home/$(USER)/
	chmod 500 /home/$(USER)/.ssh
	chown $(USER):$(USER) /home/$(USER)/.ssh
	chown $(USER):$(USER) /home/$(USER)/.config/fish/config.fish
	chown $(USER):$(USER) /home/$(USER)/.config/sway/config
	chown $(USER):$(USER) /home/$(USER)/.config/sway/config.toml
	chmod +x /home/$(USER)/.config/fish/jetbrains-fish.sh

autologin: cfg
	mkdir -p /etc/systemd/system/getty@tty1.service.d/
	echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/override.conf
	echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/override.conf
	echo 'ExecStart=-/usr/bin/agetty --autologin $(USER) --noclear %I $$TERM' >> /etc/systemd/system/getty@tty1.service.d/override.conf
	systemctl enable getty@tty1

grub:
	$(PACMAN) grub efibootmgr
	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
	sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg

grub-bios:
	$(PACMAN) grub
	grub-install --target=i386-pc /dev/$(DISK)$(P)1
	sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg

system: cfg
	echo $(HOSTNAME) > /etc/hostname
	mkinitcpio -P
	echo "root:root" | chpasswd
	$(PACMAN) dhcpcd iwd openssh git
	systemctl enable iwd
	systemctl enable sshd
	
	mkdir -p /etc/iwd
	echo "[General]" > /etc/iwd/main.conf
	echo "EnableNetworkConfiguration=true" >> /etc/iwd/main.conf
	echo "nameserver 1.1.1.1" >> /etc/resolv.conf
	#$(PACMAN) systemd-resolvconf
	#systemctl enable systemd-resolved
	#systemctl --user enable --now  pulseaudio.service

system_vm:
	$(PACMAN) dhcpcd dhcp
	systemctl enable dhcpcd

audio:
	$(PACMAN) pulseaudio pulsemixer

fstab: cfg
	mkdir -p /mnt/evo-pro
	echo "/dev/nvme0n1p1 /mnt/evo-pro ext4 rw,relatime 0 0" >> /etc/fstab
	chown $(USER) /mnt/evo-pro

libvirt: cfg
	$(PACMAN) qemu libvirt virt-manager polkit edk2-ovmf dnsmasq
	pacman -S iptables-nft
	usermod -a -G libvirt,kvm $(USER)
	systemctl enable iptables
	systemctl enable dnsmasq
	systemctl enable libvirtd
	#virsh net-autostart default
	#virsh net-start default
	sed -i 's/MODULES=()/MODULES=(vfio_pci vfio vfio_iommu_type1 vfio_virqfd)/' /etc/mkinitcpio.conf
	mkinitcpio -P
	echo "options vfio-pci ids=10de:1b06,10de:10ef" >> /etc/modprobe.d/vfio.conf
	-sed -i 's/#user = "root"/user = "$(USER)"/' /etc/libvirt/qemu.conf

.ONESHELL:
yay: cfg
	git clone https://aur.archlinux.org/yay.git
	chown -R $(USER):$(USER) yay/
	pushd yay
	sudo -u $(USER) makepkg -si --noconfirm
	popd
	rm -rf yay

.ONESHELL:
sway: cfg
	$(PACMAN) sway i3status-rust ttf-font-awesome fzf xorg-xwayland swaybg
	$(YAY) sway-launcher-desktop-git

.ONESHELL:
i3: cfg
	$(YAY) xf86-video-qxl xorg xorg-server xorg-xinit i3 dmenu spice-vdagent xrandr autorandr
	echo "spice-vdagent &" > /home/$(USER)/.xinitrc
	echo "" >> /home/$(USER)/.xinitrc
	echo "exec i3" >> /home/$(USER)/.xinitrc
	sudo systemctl enable autorandr.service
	#xrandr --auto --output Virtual-1 --mode 1916x989
	#autorandr --save default
	cp /home/$(USER)/.config/.xinitrc /home/$(USER)
	chmod +x /home/$(USER)/.xinitrc
	cp /home/$(USER)/.config/fish/config.fish.x /home/$(USER)/.config/fish/config.fish
	chown $(USER):$(USER) /home/$(USER)/.config/fish/config.fish

app: cfg
	$(PACMAN) wget git firefox alacritty tmux thunar gvfs thunar-volman thunar-archive-plugin python ansible

idea: cfg
	$(YAY) intellij-idea-ultimate-edition intellij-idea-ultimate-edition-jre
	sudo ln -s /usr/bin/intellij-idea-ultimate-edition /usr/bin/idea

.ONESHELL: cfg
spotify:
	$(YAY) spotify

