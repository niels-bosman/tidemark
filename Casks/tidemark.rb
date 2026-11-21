cask "tidemark" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/niels-bosman/tidemark/releases/download/v#{version}/Tidemark.zip"
  name "Tidemark"
  desc "CPU, RAM, disk, battery and network meters for the menu bar"
  homepage "https://github.com/niels-bosman/tidemark"

  depends_on macos: ">= :ventura"

  app "Tidemark.app"

  # The app is not notarized; clearing quarantine lets it open without the Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Tidemark.app"]
  end

  zap trash: "~/Library/Preferences/local.tidemark.plist"
end
