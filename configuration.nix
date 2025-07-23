# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./lanzaboote.nix
    ];


#Bootloader
boot = { 
kernelParams = [ "quiet" ];
loader.systemd-boot.enable = true;
loader.efi.canTouchEfiVariables = true;
loader.timeout = 1;
};

  networking.hostName = "X23O"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # firewall nftables
  networking.nftables.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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
  #services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
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
  users.users.kafu = {
    isNormalUser = true;
    description = "k2";
    extraGroups = [ "networkmanager" "libvirtd" ];
    packages = with pkgs; [
      thunderbird
      libreoffice 	
      stremio
      spotify
    ];
  };

# Enable doas instead of sudo
    security.sudo.enable = false;
    security.doas.enable = true;
    security.doas.extraRules = [{
	users = [ "kafu" ];
	keepEnv = true;
        persist = true;
     }];

virtualisation.libvirtd.enable = true;
programs.dconf.enable = true;


  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "kafu";

  # Install firefox.
programs.firefox.enable = true;


  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
virt-manager
kdePackages.ark
kdePackages.kcalc
ffmpeg
system-config-printer
spice
spice-gtk
win-spice
spice-vdagent
nftables
gparted
lm_sensors
lynis
sbctl
niv
fastfetch
neovim
openh264
ungoogled-chromium
htop
intel-gpu-tools
apparmor-profiles
  ];

hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
   #   intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver # For older processors. LIBVA_DRIVER_NAME=i965
    ];
  };
#  environment.sessionVariables = { LIBVA_DRIVER_NAME = "i965"; }; # Optionally, set the environment variable


fonts.packages = with pkgs; [
source-code-pro
nerd-fonts.fira-code
nerd-fonts.droid-sans-mono
nerd-fonts.jetbrains-mono
liberation_ttf
fira-code
fira-code-symbols
    ];
 
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
security.apparmor.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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
  system.stateVersion = "25.05"; # Did you read the comment?

}
