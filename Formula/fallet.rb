class Fallet < Formula
  desc "Floating file shelf for moving files around Finder"
  homepage "https://github.com/Shinvitiya/Fallet"
  url "https://github.com/Shinvitiya/Fallet/archive/refs/tags/source-v1.5.tar.gz"
  sha256 "5f08b1dd5ce26991301ae39faa1849206c583fcdbf5a9b2c87931c17e7d0c945"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "zsh", "build.sh"
    prefix.install "dist/Fallet.app"

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
      Its icon then appears in the menu bar.
    EOS
  end

  test do
    assert_path_exists prefix/"Fallet.app/Contents/MacOS/Fallet"
    system "codesign", "--verify", "--deep", "--strict", prefix/"Fallet.app"
  end
end
