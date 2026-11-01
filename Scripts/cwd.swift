import Darwin
for a in CommandLine.arguments.dropFirst() {
    let pid = Int32(a)!
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    let ok = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size
    let path = ok ? withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) } : ""
    print(pid, path)
}
