class Mole < Formula
  desc "Mole - Clean your Mac"
  homepage "https://github.com/tw93/mole"
  license "MIT"
  head "https://github.com/tw93/mole.git", branch: "main"

  def install
    bin.install "mole"
  end

  test do
    assert_match "Mole", shell_output("#{bin}/mole --help", 0)
  end
end
