'use strict';
// Runs before UIApplication/main. No ObjC bridge, forced dlopen, or custom mapping.
const keepCaptureAlive = __HAKU_KEEP_ALIVE__;
if (keepCaptureAlive) {
    for (const name of ['exit', '_exit', 'abort']) {
        const address = Module.findGlobalExportByName(name);
        if (address) Interceptor.replace(address, new NativeCallback(() => {}, 'void', name === 'abort' ? [] : ['int']));
    }
    const raiseAddress = Module.findGlobalExportByName('raise');
    if (raiseAddress) Interceptor.replace(raiseAddress, new NativeCallback(() => 0, 'int', ['int']));
    const killAddress = Module.findGlobalExportByName('kill');
    if (killAddress) {
        const originalKill = new NativeFunction(killAddress, 'int', ['int', 'int']);
        Interceptor.replace(killAddress, new NativeCallback((pid, signal) => {
            return pid === Process.id || pid === 0 ? 0 : originalKill(pid, signal);
        }, 'int', ['int', 'int']));
    }
    Interceptor.flush();
}
const appPath = Process.mainModule.path.slice(0, Process.mainModule.path.indexOf('.app/') + 4);
if (!appPath.endsWith('.app')) throw new Error('Main image is not an application bundle');
function identity(module) {
    const base = module.base;
    if (base.readU32() !== 0xfeedfacf) throw new Error('Unsupported runtime Mach-O');
    const count = base.add(16).readU32(), size = base.add(20).readU32();
    if (size > 16 * 1024 * 1024 || count > size / 8) throw new Error('Invalid runtime commands');
    let cursor = 32, uuid = null;
    const segments = [];
    for (let i = 0; i < count; i++) {
        const command = base.add(cursor), kind = command.readU32(), length = command.add(4).readU32();
        if (length < 8 || cursor + length > 32 + size) throw new Error('Invalid runtime command size');
        if (kind === 0x1b) {
            if (length < 24 || uuid !== null) throw new Error('Invalid runtime UUID');
            uuid = Array.from(new Uint8Array(command.add(8).readByteArray(16)), b => b.toString(16).padStart(2, '0')).join('');
        }
        if (kind === 0x19) {
            if (length < 72) throw new Error('Invalid segment');
            segments.push({vm: command.add(24).readU64(), file: command.add(40).readU64().toNumber(), size: command.add(48).readU64().toNumber()});
        }
        cursor += length;
    }
    const headerSegment = segments.find(s => s.file === 0 && s.size >= 32 + size);
    if (uuid === null || !headerSegment) throw new Error('Missing UUID/header segment');
    return {path: module.path, uuid, cpuType: base.add(4).readU32(), cpuSubtype: base.add(8).readU32(), segments, headerVM: headerSegment.vm};
}
const modules = Process.enumerateModules().filter(m => m.path.startsWith(appPath + '/'));
const images = modules.map(identity);
send({kind: 'inventory', appPath, mainPath: Process.mainModule.path, pid: Process.id,
      images: images.map(m => ({path:m.path, uuid:m.uuid, cpuType:m.cpuType, cpuSubtype:m.cpuSubtype}))});

recv('capture', message => {
    try {
        for (const request of message.payload.requests) {
            const image = images.find(m => m.path === request.path && m.uuid === request.uuid);
            if (!image) throw new Error('Requested module identity is not loaded');
            let done = 0;
            while (done < request.size) {
                const offset = request.offset + done;
                const segment = image.segments.find(s => offset >= s.file && offset < s.file + s.size);
                if (!segment) throw new Error('Encryption range has an unmapped file interval');
                const count = Math.min(256 * 1024, request.size - done, segment.file + segment.size - offset);
                const address = modules.find(m => m.path === image.path).base
                    .add(ptr('0x' + segment.vm.sub(image.headerVM).toString(16)))
                    .add(offset - segment.file);
                const bytes = address.readByteArray(count);
                send({kind: 'chunk', id: request.id, offset: done, size: count}, bytes);
                let accepted = false;
                recv('ack', ack => { accepted = ack.payload.id === request.id && ack.payload.offset === done; }).wait();
                if (!accepted) throw new Error('Capture acknowledgement mismatch');
                done += count;
            }
        }
        send({kind: 'complete'});
    } catch (error) { send({kind: 'failure', error: String(error.stack || error)}); }
});
