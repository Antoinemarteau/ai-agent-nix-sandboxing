{ pkgs, home-manager, devshellRoot, devshellUser }:

home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [({ config, ... }: {
    home.username = devshellUser;
    home.homeDirectory = devshellRoot + "/.home";
    home.stateVersion = "25.11";

    programs.zsh = {
      enable = true;

      dotDir = "${config.xdg.configHome}/zsh";

      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;

      history = {
        path = "${config.xdg.stateHome}/zsh_history";
        size = 50000;
      };

      oh-my-zsh = {
        enable = true;
        plugins = [ "git" ];
        theme = "agnoster";
      };
    };
  })];
}
