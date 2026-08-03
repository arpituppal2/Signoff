class Signoff < Formula
  desc "Witty email signoffs generated on-device via Apple Foundation Models"
  homepage "https://github.com/arpituppal2/Signoff"
  url "https://github.com/arpituppal2/Signoff/releases/download/v1.0.0/Signoff.dmg"
  sha256 "2e7b81d475126b7ffe026ebfbab406f9bc2ae8f9f10e56f8c5c181ec05ca1688"
  version "1.0.0"
  license "MIT"

  # Requires macOS 26 or later for Apple Foundation Models (on-device generation)
  depends_on macos: ">= 26"

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
      Signoff requires macOS 26 or later for Apple Foundation Models.
      The app installs to /Applications/Signoff.app

      On first launch:
      1. Grant Accessibility permission (System Settings → Privacy & Security → Accessibility)
      2. Grant Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring)
      3. Enable Apple Intelligence (System Settings → Apple Intelligence & Siri)

      Global shortcuts (generate & paste in the given voice):
        ⌃⌥1 = Normal voice
        ⌃⌥2 = Professional voice
        ⌃⌥3 = Cynical voice
        ⌃⌥` = Toggle the Signoff menu
        ⌃⌥, = Open Settings
    EOS
  end

  test do
    # Signoff is a menu-bar (LSUIElement) app: launching the binary starts a
    # GUI session and never exits, so we verify the install by bundle presence
    # rather than invoking the executable (which would hang `brew test`).
    assert_predicate Pathname("/Applications/Signoff.app"), :exist?
    assert_predicate Pathname("/Applications/Signoff.app/Contents/MacOS/Signoff"), :exist?
  end
end
