
function startWorkerJsShim(reader, writer, sentinel) {
    // In a normal world, we'd spawn the worker here as a child worker.
    // However Safari doesn't support nested workers, so we have to
    // proxy them through the main thread
    // final worker = Worker('worker.dart.js');

    /// Posts a message to the main thread to start a new worker and passes a
    /// Message Port.
    self.postMessage({
        'type': '__absurd:spawn-idb-worker',
        "argBuffer":writer,
        "resultBuffer":reader,
        "initSemaphore":sentinel

    },);


}

function startFileWorkerJsShim(worker,  argBuffer, resultBuffer, initSemaphore) {
    worker.postMessage(
        {
            "type": "__absurd:setup-file-channel",/* "port": port,*/
            "argBuffer": resultBuffer,
            "resultBuffer": argBuffer,
            "initSemaphore": initSemaphore
        },
        /* []*/);

}