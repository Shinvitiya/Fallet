class Fallet < Formula
  desc "Floating file shelf for moving files around Finder"
  homepage "https://github.com/Shinvitiya/Fallet"
  url "https://github.com/Shinvitiya/Fallet/archive/refs/tags/v1.6.2.tar.gz"
  sha256 "e1fe2da95d2ccce68abe9aaaea569018f4a12989c6b3d5d5c19f2300a5da707d"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "zsh", "build.sh"
    prefix.install "dist/Fallet.app"
    libexec.install ".build/FalletLauncher"
    bin.install "Scripts/fallet-app-link.py" => "fallet-app-link"
    (bin/"fallet-app-link").chmod 0755
    (bin/"fallet-uninstall").make_symlink "fallet-app-link"

    launcher = bin/"fallet"
    launcher.write <<~SH
      #!/bin/sh
      exec /usr/bin/open "#{opt_prefix}/Fallet.app"
    SH
    launcher.chmod 0755
  end

  def caveats
    <<~EOS
      Fallet was built locally from source. Launch it with:
        fallet
      To add Fallet to /Applications and the macOS app launcher, run:
        fallet-app-link link
      Its icon then appears in the menu bar. For a complete uninstall, run:
        fallet-uninstall
      This also deletes Fallet's saved shelf and generated images.
    EOS
  end

  test do
    assert_path_exists prefix/"Fallet.app/Contents/MacOS/Fallet"
    assert_path_exists bin/"fallet-app-link"
    assert_path_exists bin/"fallet-uninstall"
    assert_path_exists libexec/"FalletLauncher"
    system "codesign", "--verify", "--deep", "--strict", prefix/"Fallet.app"
  end
end
