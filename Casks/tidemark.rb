cask "tidemark" do
  version "1.0.0"
  sha256 "e4fcca86ef8c81376745b5308eee5d0556d6e0ee3de3c06411cf457c3d01db74"

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
