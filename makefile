.PHONY: check-cfg print-cfg cfg partition chroot datetime locale user grub system fstab libvirt sway app all

MAKEFILE_JUSTNAME := $(firstword $(MAKEFILE_LIST))
MAKEFILE_COMPLETE := $(CURDIR)/$(MAKEFILE_JUSTNAME)

CONFIGURATION_JUSTNAME := $(ARCH_INSTALL_CONFIGURATION)
CONFIGURATION_COMPLETE := $(CURDIR)/$(CONFIGURATION_JUSTNAME)

PACMAN := pacman -Sy --noconfirm

DISK := $(ARCH_INSTALL_DISK)
P := $(ARCH_INSTALL_P)

HOSTNAME := $(ARCH_INSTALL_HOSTNAME)
USER := $(ARCH_INSTALL_USER)


# CONFIGURATION

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

# END CONFIGURATION

partition: cfg
	parted /dev/$(DISK) mklabel gpt
	parted /dev/$(DISK) mkpart fat32 1M 512M
	parted /dev/$(DISK) mkpart ext4 512M 100%
	
	mkfs.fat -F 32 -n boot /dev/$(DISK)$(P)1
	mkfs.ext4 /dev/$(DISK)$(P)2 

	mount /dev/$(DISK)$(P)2 /mnt
	mkdir -p /mnt/boot
	mount /dev/$(DISK)$(P)1 /mnt/boot

	pacstrap /mnt base base-devel linux linux-firmware
	genfstab -U /mnt >> /mnt/etc/fstab

chroot:
	cp makefile /mnt/makefile
	cp configure.sh /mnt/configure.sh
	mkdir -p /mnt/var/lib/iwd
	cp /var/lib/iwd/*.psk /mnt/var/lib/iwd/
	arch-chroot /mnt source /configure.sh && make -f /makefile cfg

all: cfg datetime locale user autologin grub system fstab libvirt sway app

datetime:
	ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
	$(PACMAN) ntp
	ntpd -gq
	hwclock --systohc

locale:
	sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf
	echo "KEYMAP=us_intl" > /etc/vconsole.conf

user: cfg
	$(PACMAN) sudo neovim fish
	useradd -m $(USER) -s /bin/fish
	usermod -a -G wheel,video,input $(USER)
	echo "$(USER):$(USER)" | chpasswd
	ln -s /usr/bin/nvim /usr/bin/vi
	ln -s /usr/bin/nvim /usr/bin/vim
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
	mkdir -p /home/$(USER)/.config/fish/
	echo '# Start X at login' > /home/$(USER)/.config/fish/config.fish
	echo 'if status is-login' >> /home/$(USER)/.config/fish/config.fish
	echo '  if test -z "$$DISPLAY" -a "$$XDG_VTNR" = 1' >> /home/$(USER)/.config/fish/config.fish
	echo '    sway' >> /home/$(USER)/.config/fish/config.fish
	echo '  end' >> /home/$(USER)/.config/fish/config.fish
	echo 'end' >> /home/$(USER)/.config/fish/config.fish
	chown -R $(USER):$(USER) /home/$(USER)/
	chown $(USER):$(USER) /home/$(USER)/.config/fish/config.fish

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

system: cfg
	echo $(HOSTNAME) > /etc/hostname
	mkinitcpio -P
	echo "root:root" | chpasswd
	$(PACMAN) iwd openssh
	systemctl enable iwd
	systemctl enable sshd
	mkdir -p /etc/iwd
	echo "[General]" > /etc/iwd/main.conf
	echo "EnableNetworkConfiguration=true" >> /etc/iwd/main.conf
	echo "nameserver 1.1.1.1" >> /etc/resolv.conf

fstab: cfg
	mkdir -p /mnt/evo-pro
	echo "/dev/nvme0n1p1 /mnt/evo-pro ext4 rw,relatime 0 0" >> /etc/fstab
	chown $(USER) /mnt/evo-pro

libvirt: cfg
	$(PACMAN) qemu libvirt firewalld virt-manager polkit edk2-ovmf dnsmasq
	usermod -a -G libvirt,kvm $(USER)
	systemctl enable libvirtd firewalld
	#virsh net-autostart default
	#sudo virsh net-list --all
	#sudo vi /etc/mkinitcpio.conf
	#sudo vi /etc/modprobe.d/vfio.conf
	#ls /dev/input/by-id/
	#sudo vi /etc/libvirt/qemu.conf
	#sudo pacman -S pulseaudio
	#sudo systemctl --user enable --now  pulseaudio.service

sway: cfg
	pacman -S --noconfirm sway i3status-rust bemenu
	#mkdir -p /home/$(USER)/.config/sway
	#touch /home/$(USER)/.config/sway/config
	
app:
	pacman -S --noconfirm firefox alacritty tmux

