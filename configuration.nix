# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
 ];


  # Bootloader.
  boot.loader.limine.enable = true;
  boot.loader.limine.secureBoot.enable = true;
 # boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "xz30"; # Define your hostname.
  networking.enableIPv6 = false;
  networking.dhcpcd.enable = false;
  networking.nameservers = [ "9.9.9.11" "1.1.1.2" ];
 # networking.nameservers = [ "94.140.14.14" "94.140.15.15" ]; # AdGuard DNS
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";



networking.wireless.iwd = {
  enable = true;
 settings.General.EnableNetworkConfiguration = true;
  settings = {
    General = {
      # Mantém o anonimato gerando um MAC por rede
      AddressRandomization = "once";
      AddressRandomizationRange = "full";
    };
    Network = {
      # DESATIVA explicitamente o processamento de IPv6 no iwd
      EnableIPv6 = false;
    };
	Settings = {
      AutoConnect = true;
    };
  };
};

zramSwap = {
    enable = true;
    priority = 100;
    algorithm = "lz4";
    memoryPercent = 50;
  };

  # Enable networking
  #networking.networkmanager.enable = true;
  #networking.networkmanager.wifi.backend = "iwd";
  
  # Set your time zone.
  time.timeZone = "Europe/Lisbon";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_PT.UTF-8";
    LC_IDENTIFICATION = "pt_PT.UTF-8";
    LC_MEASUREMENT = "pt_PT.UTF-8";
    LC_MONETARY = "pt_PT.UTF-8";
    LC_NAME = "pt_PT.UTF-8";
    LC_NUMERIC = "pt_PT.UTF-8";
    LC_PAPER = "pt_PT.UTF-8";
    LC_TELEPHONE = "pt_PT.UTF-8";
    LC_TIME = "pt_PT.UTF-8";
  };



  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
 # services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "br,gb";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "uk";

  # Enable CUPS to print documents.
  services.printing = {
        enable = true;
        drivers = [ pkgs.gutenprint pkgs.hplip ];
    };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."xefe" = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "xefe";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" ];
    packages = with pkgs; [
 kdePackages.kate
 kdePackages.ark
 kdePackages.kcalc
 thunderbird
 libreoffice
 spotify
whatsapp-electron
vlc
    ];
  };

# Enable doas instead of sudo
    security.sudo.enable = false;
    security.doas.enable = true;
    security.doas.extraRules = [{
	users = [ "xefe" ];
	keepEnv = true;
        persist = true;
     }];

# Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "xefe";

  # Ativa o Zsh no sistema
  programs.zsh = {
  enable = true;
  interactiveShellInit = "ufetch";	   
  enableLsColors = true;
  promptInit = ''
    # %F{cor} inicia a cor, %f termina. %n é utilizador, %m é máquina, %~ é a pasta.
    PROMPT="%F{green}%n%f@%F{blue}%m%f:%F{cyan}%~%f$ "
  '';
  # Ativa o realce de sintaxe colorido ao digitar
  syntaxHighlighting.enable = true;
  
  # Ativa sugestões cinzentas baseadas no histórico de comandos
  autosuggestions.enable = true;
  
# Adicione os seus atalhos personalizados aqui
  shellAliases = {
    ll = "ls -l";
    la = "ls -la";
    nix-switch = "sudo nixos-rebuild switch";
    nix-clean = "sudo nix-env --delete-generations old && sudo nix-store --gc";
    dmesg = "sudo dmesg";
    ss = "ss -tunap";
    sudo = "doas";	
  };

};

programs.foot = {
  enable = true;
  settings = {
    main = {
      # Sets the font and increases the size (e.g., to 14)
      font = "Hack:size=15";
      
      # Forces foot to launch directly into full-screen mode
      initial-window-mode = "maximized";
    };
  };
};


virtualisation.libvirtd.enable = true;
programs.virt-manager.enable = true;
#programs.mangowc.enable = true;

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
microcode-intel
nftables
htop
intel-gpu-tools
apparmor-profiles 
sbctl
gparted
lm_sensors
lynis
ufetch
ffmpeg
openh264
git
#papirus-icon-theme
papirus-nord
dnsmasq
#stremio-linux-shell
iwgtk
bat
neovim
foot
 ];

hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
   #   intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver # For older processors. LIBVA_DRIVER_NAME=i965
    ];
  };
#  environment.sessionVariables = { LIBVA_DRIVER_NAME = "i965"; }; # Optionally, set the environment variable

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

fonts.packages = with pkgs; [
source-code-pro
corefonts
    ];

security.apparmor.enable = true;
security.apparmor.killUnconfinedConfinables = true;

  # List services that you want to enable:
#services.thermald.enable = true;

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
   networking.firewall.enable = true;
   networking.firewall.trustedInterfaces = [ "virbr0" ];
   networking.firewall.logRefusedPackets = true;
# Do the garbage collection & optimisation weekly.
nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 10d";
  };

nix.optimise.automatic = true;

system.autoUpgrade.enable = true;
system.autoUpgrade.dates = "weekly";



  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

}
