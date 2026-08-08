class Signoff < Formula
  desc "Witty email signoffs generated on-device via Apple Foundation Models"
  homepage "https://github.com/arpituppal2/Signoff"
  url "https://github.com/arpituppal2/Signoff/releases/download/v10.0/Signoff.dmg"
  sha256 "52513ba757bd3a4908565fdd222c6c690f45e1cda40d7fdc33e5bf7d6942a9db"
  version "10.0"
  license "MIT"

  # Requires macOS 15 (Sequoia) or later for Apple Foundation Models
  depends_on macos: ">= 15"

  def install
    # Use diskutil for macOS 26+ compatibility
    system "diskutil", "image", "attach", "--mountOptions", "nobrowse,readOnly", cached_download
    # Find the mounted volume
    volumes = Dir.glob("/Volumes/Signoff*")
    if volumes.empty?
      raise "Failed to mount DMG"
    end
    mount_point = volumes.first
    system "cp", "-R", "#{mount_point}/Signoff.app", "/Applications/"
    system "diskutil", "image", "detach", mount_point
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
