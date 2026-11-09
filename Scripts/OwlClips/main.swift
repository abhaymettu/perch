import AppKit

// Renders every scene in the owl's catalogue to PNG frames, straight from the
// same performer and renderer the menu bar uses. Scripts/owl-clips.sh builds
// this and turns the frames into clips and contact sheets.
//
//   owlclips <out-dir> [fps] [scene name ...]
//
// Per scene and bar colour it writes two sequences: `real` at the menu bar's
// own 2 pixels a point, and `big` at 16.

let arguments = CommandLine.arguments.dropFirst()
guard let out = arguments.first else {
    FileHandle.standardError.write(Data("usage: owlclips <out-dir> [fps] [scene ...]\n".utf8))
    exit(2)
}
let fps = arguments.dropFirst().first.flatMap(Double.init) ?? 60
let wanted = Set(arguments.dropFirst(2))

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

var index: [[String: Any]] = []
for scene in OwlRepertoire.catalogue where wanted.isEmpty || wanted.contains(scene.name) {
    let poses = scene.poses(fps: fps)
    let slug = scene.name.replacingOccurrences(of: " ", with: "-")
    for (bar, dark) in [("dark", true), ("light", false)] {
        for (size, pixels) in [("real", CGFloat(2)), ("big", 16)] {
            let directory = "\(out)/\(slug)/\(bar)-\(size)"
            try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (frame, pose) in poses.enumerated() {
                write(MenuBarIcon.bitmap(pose: pose, isDarkMenuBar: dark, pixelsPerPoint: pixels)!,
                      to: String(format: "%@/%04d.png", directory, frame))
            }
        }
    }
    index.append(["name": scene.name, "slug": slug, "frames": poses.count,
                  "seconds": Double(poses.count) / fps])
}
let json = try! JSONSerialization.data(withJSONObject: ["fps": fps, "scenes": index], options: [.prettyPrinted])
try! json.write(to: URL(fileURLWithPath: "\(out)/index.json"))
print("\(index.count) scenes at \(Int(fps)) fps in \(out)")
