class Signoff < Formula
  desc "Witty email signoffs generated on-device via Apple Foundation Models"
  homepage "https://github.com/arpituppal2/Signoff"
  url "https://github.com/arpituppal2/Signoff/releases/download/v10.0/Signoff.dmg"
  sha256 "380cec669835be3b6b7558ea06a7817bff7d906366802692110e23ded5317ff0" # Will be updated after release assets are uploaded
  version "10.0"
  license "MIT"

  depends_on macos: ">= :sequoia"

  def install
    # Mount the DMG and copy the .app to /Applications
    system "hdiutil", "attach", cached_download, "-nobrowse", "-quiet", "-mountpoint", "/tmp/signoff-dmg"
    system "cp", "-R", "/tmp/signoff-dmg/Signoff.app", "/Applications/"
    system "hdiutil", "detach", "/tmp/signoff-dmg", "-quiet"
  end

  def caveats
    <<~EOS
      Signoff requires macOS 26 (Sequoia) or later for Apple Foundation Models.
      The app installs to /Applications/Signoff.app

      On first launch:
      1. Grant Accessibility permission (System Settings → Privacy & Security → Accessibility)
      2. Grant Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring)
      3. Enable Apple Intelligence (System Settings → Apple Intelligence & Siri)

      Global shortcuts:
        ⌃⌥1 = Normal voice
        ⌃⌥2 = Cynical voice
        ⌃⌥3 = Professional voice
        ⌃⌥F = Generate & Paste
    EOS
  end

  test do
    assert_predicate Pathname("/Applications/Signoff.app"), :exist?
    system "/Applications/Signoff.app/Contents/MacOS/Signoff", "--version"
  end
end
