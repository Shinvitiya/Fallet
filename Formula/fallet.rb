class Fallet < Formula
  desc "Floating file shelf for moving files around Finder"
  homepage "https://github.com/Shinvitiya/Fallet"
  url "https://github.com/Shinvitiya/Fallet/archive/refs/tags/source-v1.3.tar.gz"
  sha256 "abec403c5e5e9819d4e24400b8b471e656cd2a4f56e0a4f491b9eb30d655425f"
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
