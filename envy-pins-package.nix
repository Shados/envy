{ lib, runCommand }:

runCommand "envy-pins" {
  # dontPatchShebangs = true;
  preferLocalBuild = true;
  src = builtins.filterSource
    (path: type:
       builtins.elem (baseNameOf path) [ "envy-pins" "config-nvim-builder.moon" ]
    || lib.hasSuffix ".nix" path)
    ./.;
} ''
mkdir -p $out/bin/
mkdir -p $out/share/
echo cp -r $src/ $out/share/envy
cp -r $src/ $out/share/envy
cat << EOF > $out/bin/envy-pins
#!/usr/bin/env sh
# Wrapper script to work around Nix not using realpath() to locate relative Nix
# files for nix-shell shebangs
exec -a "\$0" "$out/share/envy/envy-pins" "\$@"
EOF
chmod +x $out/bin/envy-pins
chmod +x $out/share/envy/envy-pins
''
