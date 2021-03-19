{ pkgs ? import <nixpkgs> { } }:
with pkgs.lib;
let
  # Some Python deps not in nixpkgs {{{
  git-url-parse = with pkgs.python3Packages; buildPythonPackage rec {
    name = "${pname}-${version}";
    pname = "git-url-parse";
    version = "1.2.2";
    src = fetchPypi {
    # src = pkgs.fetchurl {
    #   url = "https://files.pythonhosted.org/packages/09/cc/3dfd545b9a7290baf869e60d7f006076bddd50fc1f00c40ff0649b705b39/git-url-parse-1.1.0.tar.gz";
      inherit pname version;
      sha256 = "05zi8n2aj3fsy1cyailf5rn21xv3q15bv8v7xvz3ls8xxcx4wpvv";
    };
    doCheck = false;
    buildInputs = [];
    propagatedBuildInputs = [
      setuptools pbr
    ];
    meta = with pkgs.lib; {
      homepage = "https://github.com/retr0h/git-url-parse";
      license = licenses.mit;
      description = "git-url-parse - A simple GIT URL parser.";
    };
  };
  # }}}
in
pkgs.mkShell {
  nativeBuildInputs = [
    (pkgs.python3.withPackages(ps: with ps; [
      git-url-parse
    ]))
  ];
}
