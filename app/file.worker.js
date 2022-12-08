let isProbablySafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);


//----------------------------------------------------------------------------------------------------------------------
// start sqlite utils
let LOCK_TYPES = {
    NONE: 0,
    SHARED: 1,
    RESERVED: 2,
    PENDING: 3,
    EXCLUSIVE: 4
};

function getPageSize(bufferView) {
    // See 1.3.2 on https://www.sqlite.org/fileformat.html The page size
    // is stored as a 2 byte integer at the 16th byte. It's stored as
    // big-endian so the first byte is the larger one. Combine it into a
    // single integer.
    let int1 = bufferView[16];
    let int2 = bufferView[17];
    return (int1 << 8) + int2;
}

function isSafeToWrite(localData, diskData) {
    if (localData != null && diskData != null) {
        let localView = new Uint8Array(localData);
        let diskView = new Uint8Array(diskData);

        // See
        // https://github.com/sqlite/sqlite/blob/master/src/pager.c#L93-L96
        // (might be documented somewhere? I didn't see it this clearly in
        // the docs). At least one of these bytes change when sqlite3 writes
        // data. We can check this against our in-memory data to see if it's
        // safe to write (if something changes underneath us, it's not)
        for (let i = 24; i < 40; i++) {
            if (localView[i] !== diskView[i]) {
                return false;
            }
        }
        return true;
    }

    // One of them is null, so it's only safe if to write if both are
    // null, otherwise they are different
    return localData == null && diskData == null;
}


//----------------------------------------------------------------------------------------------------------------------


//----------------------------------------------------------------------------------------------------------------------
// start shared channel

let FINALIZED = 0xdeadbeef;

let WRITEABLE = 0;
let READABLE = 1;

class Reader {
    constructor(
        buffer,
        {initialOffset = 4, useAtomics = true, stream = true, debug, name} = {}
    ) {
        this.buffer = buffer;
        this.atomicView = new Int32Array(buffer);
        this.offset = initialOffset;
        this.useAtomics = useAtomics;
        this.stream = stream;
        this.debug = debug;
        this.name = name;
    }

    log(...args) {
        if (this.debug) {
            console.log(`[reader: ${this.name}]`, ...args);
        }
    }

    waitWrite(name, timeout = null) {
        if (this.useAtomics) {
            this.log(`waiting for ${name}`);

            while (Atomics.load(this.atomicView, 0) === WRITEABLE) {
                if (timeout != null) {
                    if (
                        Atomics.wait(this.atomicView, 0, WRITEABLE, timeout) === 'timed-out'
                    ) {
                        throw new Error('timeout');
                    }
                }

                Atomics.wait(this.atomicView, 0, WRITEABLE, 500);
            }

            this.log(`resumed for ${name}`);
        } else {
            if (this.atomicView[0] !== READABLE) {
                throw new Error('`waitWrite` expected array to be readable');
            }
        }
    }

    flip() {
        this.log('flip');
        if (this.useAtomics) {
            let prev = Atomics.compareExchange(
                this.atomicView,
                0,
                READABLE,
                WRITEABLE
            );

            if (prev !== READABLE) {
                throw new Error('Read data out of sync! This is disastrous');
            }

            Atomics.notify(this.atomicView, 0);
        } else {
            this.atomicView[0] = WRITEABLE;
        }

        this.offset = 4;
    }

    done() {
        this.waitWrite('done');

        let dataView = new DataView(this.buffer, 0);
        let bytes = [];

        for (let i = 0; i < 100; i++) {
            bytes[i] = dataView.getUint8(i);
        }

        let done = dataView.getUint32(this.offset, true) === FINALIZED;
        if (done) {
            this.log('done');
            this.flip();
        }

        return done;
    }

    peek(fn) {
        this.peekOffset = this.offset;
        let res = fn();
        this.offset = this.peekOffset;
        this.peekOffset = null;
        return res;
    }

    string(timeout) {


        // waitWrite('string', timeout: timeout, debugTag: debugTag);
        //
        // var byteLength = _int32(debugTag: debugTag);
        // var uint8StringBytes = atomicView.buffer.asUint8List(8, byteLength);
        // var str = utf8.decode(uint8StringBytes);
        //
        // offset += closestNumber(byteLength, 4);
        //
        // if (peekOffset == null) {
        //     flip(debugTag: debugTag);
        // }
        // return str;
        this.waitWrite('string', timeout);

        let byteLength = this._int32();
        let uint8StringBytes = new DataView(this.buffer, this.offset, byteLength);
        let chars = [];
        for (let i = 0; i < byteLength; i++) {
            chars.push(uint8StringBytes.getUint8(i));
        }
        let str = String.fromCharCode.apply(null, chars);
        this.log('string', str);

        this.offset += closestNumber(byteLength, 4);

        if (this.peekOffset == null) {
            this.flip();
        }
        return str;
    }

    _int32() {
        let byteLength = 4;

        let dataView = new DataView(this.buffer, this.offset);
        let num = dataView.getInt32(0, true);
        this.log('_int32', num);

        this.offset += byteLength;
        return num;
    }

    int32() {
        this.waitWrite('int32');
        let num = this._int32();
        this.log('int32', num);

        if (this.peekOffset == null) {
            this.flip();
        }
        return num;
    }

    bytes() {
        this.waitWrite('bytes');

        let byteLength = this._int32();

        let bytes = new ArrayBuffer(byteLength);
        new Uint8Array(bytes).set(
            new Uint8Array(this.buffer, this.offset, byteLength)
        );
        this.log('bytes', bytes);

        this.offset += byteLength;

        if (this.peekOffset == null) {
            this.flip();
        }
        return bytes;
    }
}

class Writer {
    constructor(
        buffer,
        {initialOffset = 4, useAtomics = true, stream = true, debug, name} = {}
    ) {
        this.buffer = buffer;
        this.atomicView = new Int32Array(buffer);
        this.offset = initialOffset;
        this.useAtomics = useAtomics;
        this.stream = stream;

        this.debug = debug;
        this.name = name;

        if (this.useAtomics) {
            // The buffer starts out as writeable
            Atomics.store(this.atomicView, 0, WRITEABLE);
        } else {
            this.atomicView[0] = WRITEABLE;
        }
    }

    log(...args) {
        if (this.debug) {
            console.log(`[writer: ${this.name}]`, ...args);
        }
    }

    waitRead(name) {
        //let WRITEABLE = 0;
        //let READABLE = 1;
        if (this.useAtomics) {
            this.log(`waiting for ${name}`);
            // Switch to writable
            //  Atomics.store(this.atomicView, 0, 1);

            let prev = Atomics.compareExchange(
                this.atomicView,
                0,
                WRITEABLE,
                READABLE
            );

            if (prev !== WRITEABLE) {
                throw new Error(
                    'Wrote something into unwritable buffer! This is disastrous'
                );
            }

            Atomics.notify(this.atomicView, 0);

            while (Atomics.load(this.atomicView, 0) === READABLE) {
                Atomics.wait(this.atomicView, 0, READABLE, 500);
            }

            this.log(`resumed for ${name}`);
        } else {
            this.atomicView[0] = READABLE;
        }

        this.offset = 4;
    }

    finalize() {
        this.log('finalizing');
        let dataView = new DataView(this.buffer, this.offset);
        dataView.setUint32(0, FINALIZED, true);
        this.waitRead('finalize');
    }

    string(str) {
        this.log('string', str);

        let byteLength = str.length * 2;
        this._int32(byteLength);

        let dataView = new DataView(this.buffer, this.offset, byteLength);
        for (let i = 0; i < str.length; i++) {
            dataView.setUint16(i * 2, str.charCodeAt(i));
        }

        this.offset += byteLength;
        this.waitRead('string');
    }

    _int32(num) {
        let byteLength = 4;

        let dataView = new DataView(this.buffer, this.offset);
        dataView.setInt32(0, num, true);
        this.offset += byteLength;
    }

    int32(num) {
        this.log('int32', num);
        this._int32(num);
        this.waitRead('int32');
    }

    bytes(buffer) {
        this.log('bytes', buffer);

        let byteLength = buffer.byteLength;
        this._int32(byteLength);
        new Uint8Array(this.buffer, this.offset).set(new Uint8Array(buffer));

        this.offset += byteLength;
        this.waitRead('bytes');
    }
}

function closestNumber(n, m) {
    return (m * Math.ceil((n / m)));
}


// End shared channel
//----------------------------------------------------------------------------------------------------------------------


// Don't need a map anymore, we use a worker per file
let openDbs = new Map();
let transactions = new Map();

function assert(cond, msg) {
    if (!cond) {
        throw new Error(msg);
    }
}

// We use long-lived transactions, and `Transaction` keeps the
// transaction state. It implements an optimal way to perform
// read/writes with knowledge of how sqlite asks for them, and also
// implements a locking mechanism that maps to how sqlite locks work.
class Transaction {
    constructor(db, initialMode = 'readonly') {
        this.db = db;
        this.trans = this.db.transaction(['data'], initialMode);
        this.store = this.trans.objectStore('data');
        this.lockType =
            initialMode === 'readonly' ? LOCK_TYPES.SHARED : LOCK_TYPES.EXCLUSIVE;

        // There is no need for us to cache blocks. Use sqlite's
        // `cache_size` for that and it will automatically do it. However,
        // we do still keep a cache of the first block for the duration of
        // this transaction because of how locking works; this avoids a
        // few extra reads and allows us to detect changes during
        // upgrading (see `upgradeExclusive`)
        this.cachedFirstBlock = null;

        this.cursor = null;
        this.prevReads = null;
    }

    async prefetchFirstBlock(timeout) {
        // TODO: implement timeout

        // Get the first block and cache it
        let block = await this.get(0);
        this.cachedFirstBlock = block;
        return block;
    }

    async waitComplete() {
        return new Promise((resolve, reject) => {
            // Eagerly commit it for better perf. Note that **this assumes
            // the transaction is open** as `commit` will throw an error if
            // it's already closed (which should never be the case for us)
            this.commit();

            if (this.lockType === LOCK_TYPES.EXCLUSIVE) {
                // Wait until all writes are committed
                this.trans.oncomplete = e => resolve();

                // TODO: Is it OK to add this later, after an error might have
                // happened? Will it hold the error and fire this when we
                // attached it? We might want to eagerly create the promise
                // when creating the transaction and return it here
                this.trans.onerror = e => reject(e);
            } else {
                if (isProbablySafari) {
                    // Safari has a bug where sometimes the IDB gets blocked
                    // permanently if you refresh the page with an open
                    // transaction. You have to restart the browser to fix it.
                    // We wait for readonly transactions to finish too, but this
                    // is a perf hit
                    this.trans.oncomplete = e => resolve();
                } else {
                    // No need to wait on anything in a read-only transaction.
                    // Note that errors during reads area always handled by the
                    // read request.
                    resolve();
                }
            }
        });
    }

    commit() {
        // Safari doesn't support this method yet (this is just an
        // optimization)
        if (this.trans.commit) {
            this.trans.commit();
        }
    }

    async upgradeExclusive() {
        this.commit();

        this.trans = this.db.transaction(['data'], 'readwrite');
        this.store = this.trans.objectStore('data');
        this.lockType = LOCK_TYPES.EXCLUSIVE;

        let cached0 = this.cachedFirstBlock;

        // Do a read
        let block = await this.prefetchFirstBlock(500);
        // TODO: when timeouts are implemented, detect timeout and return BUSY

        return isSafeToWrite(block, cached0);
    }

    downgradeShared() {
        this.commit();

        this.trans = this.db.transaction(['data'], 'readonly');
        this.store = this.trans.objectStore('data');
        this.lockType = LOCK_TYPES.SHARED;
    }

    async get(key) {
        return new Promise((resolve, reject) => {
            let req = this.store.get(key);
            req.onsuccess = e => {
                resolve(req.result);
            };
            req.onerror = e => reject(e);
        });
    }

    getReadDirection() {
        // There are a two ways we can read data: a direct `get` request
        // or opening a cursor and iterating through data. We don't know
        // what future reads look like, so we don't know the best strategy
        // to pick. Always choosing one strategy forgoes a lot of
        // optimization, because iterating with a cursor is a lot faster
        // than many `get` calls. On the other hand, opening a cursor is
        // slow, and so is calling `advance` to move a cursor over a huge
        // range (like moving it 1000 items later), so many `get` calls would
        // be faster. In general:
        //
        // * Many `get` calls are faster when doing random accesses
        // * Iterating with a cursor is faster if doing mostly sequential
        //   accesses
        //
        // We implement a heuristic and keeps track of the last 3 reads
        // and detects when they are mostly sequential. If they are, we
        // open a cursor and start reading by iterating it. If not, we do
        // direct `get` calls.
        //
        // On top of all of this, each browser has different perf
        // characteristics. We will probably want to make these thresholds
        // configurable so the user can change them per-browser if needed,
        // as well as fine-tuning them for their usage of sqlite.

        let prevReads = this.prevReads;
        if (prevReads) {
            // Has there been 3 forward sequential reads within 10 blocks?
            if (
                prevReads[0] < prevReads[1] &&
                prevReads[1] < prevReads[2] &&
                prevReads[2] - prevReads[0] < 10
            ) {
                return 'next';
            }

            // Has there been 3 backwards sequential reads within 10 blocks?
            if (
                prevReads[0] > prevReads[1] &&
                prevReads[1] > prevReads[2] &&
                prevReads[0] - prevReads[2] < 10
            ) {
                return 'prev';
            }
        }

        return null;
    }

    read(position) {
        let waitCursor = () => {
            return new Promise((resolve, reject) => {
                if (this.cursorPromise != null) {
                    throw new Error(
                        'waitCursor() called but something else is already waiting'
                    );
                }
                this.cursorPromise = {resolve, reject};
            });
        };

        if (this.cursor) {
            let cursor = this.cursor;

            if (
                cursor.direction === 'next' &&
                position > cursor.key &&
                position < cursor.key + 100
            ) {

                cursor.advance(position - cursor.key);
                return waitCursor();
            } else if (
                cursor.direction === 'prev' &&
                position < cursor.key &&
                position > cursor.key - 100
            ) {

                cursor.advance(cursor.key - position);
                return waitCursor();
            } else {
                // Ditch the cursor
                this.cursor = null;
                return this.read(position);
            }
        } else {
            // We don't already have a cursor. We need to a fresh read;
            // should we open a cursor or call `get`?

            let dir = this.getReadDirection();
            if (dir) {
                // Open a cursor
                this.prevReads = null;

                let keyRange;
                if (dir === 'prev') {
                    keyRange = IDBKeyRange.upperBound(position);
                } else {
                    keyRange = IDBKeyRange.lowerBound(position);
                }

                let req = this.store.openCursor(keyRange, dir);

                req.onsuccess = e => {


                    let cursor = e.target.result;
                    this.cursor = cursor;

                    if (this.cursorPromise == null) {
                        throw new Error('Got data from cursor but nothing is waiting it');
                    }
                    this.cursorPromise.resolve(cursor ? cursor.value : null);
                    this.cursorPromise = null;
                };
                req.onerror = e => {
                    console.log('Cursor failure:', e);

                    if (this.cursorPromise == null) {
                        throw new Error('Got data from cursor but nothing is waiting it');
                    }
                    this.cursorPromise.reject(e);
                    this.cursorPromise = null;
                };

                return waitCursor();
            } else {
                if (this.prevReads == null) {
                    this.prevReads = [0, 0, 0];
                }
                this.prevReads.push(position);
                this.prevReads.shift();

                return this.get(position);
            }
        }
    }

    async set(item) {
        this.prevReads = null;

        return new Promise((resolve, reject) => {
            let req = this.store.put(item.value, item.key);
            req.onsuccess = e => resolve(req.result);
            req.onerror = e => reject(e);
        });
    }

    async bulkSet(items) {
        this.prevReads = null;

        for (let item of items) {
            this.store.put(item.value, item.key);
        }
    }
}

async function loadDb(name) {
    return new Promise((resolve, reject) => {
        if (openDbs.get(name)) {
            resolve(openDbs.get(name));
            return;
        }

        let req = globalThis.indexedDB.open(name, 2);
        req.onsuccess = event => {
            let db = event.target.result;

            db.onversionchange = () => {
                // TODO: Notify the user somehow
                console.log('closing because version changed');
                db.close();
                openDbs.delete(name);
            };

            db.onclose = () => {
                openDbs.delete(name);
            };

            openDbs.set(name, db);
            resolve(db);
        };
        req.onupgradeneeded = event => {
            let db = event.target.result;
            if (!db.objectStoreNames.contains('data')) {
                db.createObjectStore('data');
            }
        };
        req.onblocked = e => console.log('blocked', e);
        req.onerror = req.onabort = e => reject(e.target.error);
    });
}

function closeDb(name) {
    let openDb = openDbs.get(name);
    if (openDb) {
        openDb.close();
        openDbs.delete(name);
    }
}

function getTransaction(name) {
    return transactions.get(name);
}

async function withTransaction(name, mode, func) {
    let trans = transactions.get(name);
    if (trans) {
        // If a transaction already exists, that means the file has been
        // locked. We don't fully support arbitrary nested transactions,
        // as seen below (we won't upgrade a `readonly` to `readwrite`
        // automatically) and this is mainly for the use case where sqlite
        // locks the db and creates a transaction for the duraction of the
        // lock. We don't actually write code in a way that assumes nested
        // transactions, so just error here
        if (mode === 'readwrite' && trans.lockType === LOCK_TYPES.SHARED) {
            throw new Error('Attempted write but only has SHARED lock');
        }
        return func(trans);
    }

    // Outside the scope of a lock, create a temporary transaction
    trans = new Transaction(await loadDb(name), mode);
    await func(trans);
    await trans.waitComplete();
}

// Locking strategy:
//
// * We map sqlite's locks onto IndexedDB's transaction semantics.
//   Read transactions may execute in parallel. Read/write
//   transactions are queued up and wait until all preceding
//   read transactions finish executing. Read transactions started
//   after a read/write transaction wait until it is finished.
//
// * IDB transactions will wait forever until they can execute (for
//   example, they may be blocked on a read/write transaction). We
//   don't want to allow sqlite transactions to wait forever, so
//   we manually timeout if a transaction takes too long to
//   start executing. This simulates the behavior of a sqlite
//   bailing if it can't require a lock.
//
// * A SHARED lock wants to read from the db. We start a read
//   transaction and read the first block, and if we read it within
//   500ms we consider the lock successful. Otherwise the lock
//   failed and we return SQLITE_BUSY. (There's no perf downside
//   to reading the first block - it has to be read anyway to check
//   bytes 24-39 for the change counter)
//
// * A RESERVED lock means the db wants to start writing (think of
//   `BEGIN TRANSACTION`). Only one process can obtain a RESERVED
//   lock at a time, but normally sqlite still leads new read locks
//   happen. It isn't until an EXCLUSIVE lock is held that reads are
//   blocked. However, since we need to guarantee only one RESERVED
//   lock at once (otherwise data could change from another process
//   within a transaction, causing faulty caches etc) the simplest
//   thing to do is go ahead and grab a read/write transaction that
//   represents the RESERVED lock. This will block all reads from
//   happening, and is essentially the same as an EXCLUSIVE lock.
//
//     * The main problem here is we can't "upgrade" a `readonly`
//       transaction to `readwrite`, but native sqlite can upgrade a
//       lock from SHARED to RESERVED. We need to start a new
//       transaction to do so, and because of that there might be
//       other `readwrite` transactions that get run during the
//       "upgrade" which invalidates the whole locking process and
//       and corrupts data.
//
// * Ideally, we could tell sqlite to skip SHARED locks entirely. We
//   don't need them since we can rely on IndexedDB's semantics.
//   Then when it wants to start writing, we get a RESERVED lock
//   without having to upgrade from SHARED. This would save us
//   the cost of a `readonly` transaction when writing; right now
//   it must open a `readonly` transaction and then immediately open
//   a `readwrite` to upgrade it. I thought of deferring opening the
//   `readonly` transaction until something is actually read, but
//   unfortunately sqlite opens it, reads the first block, and then
//   upgrades it. So there's no way around it. (We can't assume it's
//   a `readwrite` transaction at that point since that would assume
//   all SHARED locks are `readwrite`, removing the possibility of
//   concurrent reads).
//
// * Upgrading to an EXCLUSIVE lock is a noop, since we treat RESERVED
//   locks as EXCLUSIVE.
async function handleLock(writer, name, lockType) {

    let trans = transactions.get(name);
    if (trans) {
        if (lockType > trans.lockType) {
            // Upgrade SHARED to EXCLUSIVE
            assert(
                trans.lockType === LOCK_TYPES.SHARED,
                `Uprading lock type from ${trans.lockType} is invalid`
            );
            assert(
                lockType === LOCK_TYPES.RESERVED || lockType === LOCK_TYPES.EXCLUSIVE,
                `Upgrading lock type to ${lockType} is invalid`
            );

            let success = await trans.upgradeExclusive();
            writer.int32(success ? 0 : -1);
            writer.finalize();
        } else {
            // If not upgrading and we already have a lock, make sure this
            // isn't a downgrade
            assert(
                trans.lockType === lockType,
                `Downgrading lock to ${lockType} is invalid`
            );

            writer.int32(0);
            writer.finalize();
        }
    } else {
        assert(
            lockType === LOCK_TYPES.SHARED,
            `New locks must start as SHARED instead of ${lockType}`
        );

        let trans = new Transaction(await loadDb(name));
        if ((await trans.prefetchFirstBlock(500)) == null) {
            // BUSY
        }

        transactions.set(name, trans);

        writer.int32(0);
        writer.finalize();
    }
}

async function handleUnlock(writer, name, lockType) {
    let trans = getTransaction(name);

    if (lockType === LOCK_TYPES.SHARED) {
        if (trans == null) {
            throw new Error('Unlock error (SHARED): no transaction running');
        }

        if (trans.lockType === LOCK_TYPES.EXCLUSIVE) {
            trans.downgradeShared();
        }
    } else if (lockType === LOCK_TYPES.NONE) {
        // I thought we could assume a lock is always open when `unlock`
        // is called, but it also calls `unlock` when closing the file no
        // matter what. Do nothing if there's no lock currently
        if (trans) {
            // TODO: this is where an error could bubble up. Handle it
            await trans.waitComplete();
            transactions.delete(name);
        }
    }

    writer.int32(0);
    writer.finalize();
}

async function handleRead(writer, name, position) {
    return withTransaction(name, 'readonly', async trans => {
        let data = await trans.read(position);

        if (data == null) {
            writer.bytes(new ArrayBuffer(0));
        } else {
            writer.bytes(data);
        }
        writer.finalize();
    });
}

async function handleWrites(writer, name, writes) {
    return withTransaction(name, 'readwrite', async trans => {
        await trans.bulkSet(writes.map(w => ({key: w.pos, value: w.data})));

        writer.int32(0);
        writer.finalize();
    });
}

async function handleReadMeta(writer, name) {
    return withTransaction(name, 'readonly', async trans => {
        try {
            let res = await trans.get(-1);

            if (res == null) {
                // No data yet
                writer.int32(-1);
                writer.int32(4096);
                writer.finalize();
            } else {
                // let meta = res;

                // Also read the first block to get the page size
                let block = await trans.get(0);

                // There should always be a first block if we have meta, but
                // in case of a corrupted db, default to this size
                let blockSize = 4096;
                if (block) {
                    let arr = new Uint16Array(block);
                    blockSize = arr[8] * 256;
                }

                writer.int32(res.size);
                writer.int32(blockSize);
                writer.finalize();
            }
        } catch (err) {
            console.log(err);
            writer.int32(-1);
            writer.int32(-1);
            writer.finalize();
        }
    });
}

async function handleWriteMeta(writer, name, meta) {
    return withTransaction(name, 'readwrite', async trans => {
        try {
            await trans.set({key: -1, value: meta});

            writer.int32(0);
            writer.finalize();
        } catch (err) {
            console.log(err);
            writer.int32(-1);
            writer.finalize();
        }
    });
}

// `listen` continually listens for requests via the shared buffer.
// Right now it's implemented in a tail-call style (`listen` is
// recursively called) because I thought that was necessary for
// various reasons. We can convert this to a `while(1)` loop with
// and use `await` though
async function listen(reader, writer) {
    let method = reader.string();

    switch (method) {
        case 'profile-start': {
            reader.done();


            writer.int32(0);
            writer.finalize();
            listen(reader, writer);
            break;
        }

        case 'profile-stop': {
            reader.done();

            // The perf library posts a message; make sure it has time to
            // actually post it before blocking the thread again
            await new Promise(resolve => setTimeout(resolve, 1000));

            writer.int32(0);
            writer.finalize();
            listen(reader, writer);
            break;
        }

        case 'writeBlocks': {
            let name = reader.string();
            let writes = [];
            while (!reader.done()) {
                let pos = reader.int32();
                let data = reader.bytes();
                writes.push({pos, data});
            }

            await handleWrites(writer, name, writes);
            listen(reader, writer);
            break;
        }

        case 'readBlock': {
            let name = reader.string();
            let pos = reader.int32();
            reader.done();

            await handleRead(writer, name, pos);
            listen(reader, writer);
            break;
        }

        case 'readMeta': {
            let name = reader.string();
            reader.done();
            await handleReadMeta(writer, name);
            listen(reader, writer);
            break;
        }

        case 'writeMeta': {
            let name = reader.string();
            let size = reader.int32();
            // let blockSize = reader.int32();
            reader.done();
            await handleWriteMeta(writer, name, {size});
            listen(reader, writer);
            break;
        }

        case 'closeFile': {
            let name = reader.string();
            reader.done();

            // This worker is done, shut down
            writer.int32(0);
            writer.finalize();
            closeDb(name);
            self.close();
            break;
        }

        case 'lockFile': {
            let name = reader.string();
            let lockType = reader.int32();
            reader.done();

            await handleLock(writer, name, lockType);
            listen(reader, writer);
            break;
        }

        case 'unlockFile': {
            let name = reader.string();
            let lockType = reader.int32();
            reader.done();

            await handleUnlock(writer, name, lockType);
            listen(reader, writer);
            break;
        }

        default:
            throw new Error('Unknown method: ' + method);
    }
}


self.onmessage = msg => {
    switch (msg.data.type) {
        case "__absurd:setup-file-channel": {

          let  initSemaphore = msg.data.initSemaphore;
          let  initSentinelArray = new Int32Array(initSemaphore);
          let  argBuffer = msg.data.argBuffer;
          let  resultBuffer = msg.data.resultBuffer;

           let  writer = new Writer(argBuffer, {name: "args", debug: false}); // { name: 'results', debug: true
           let  reader = new Reader(resultBuffer, {name: "results", debug: false}); // { "name": 'args', debug: true });
            initSentinelArray[0] = 1;
            Atomics.notify(initSentinelArray, 0);

            listen(reader, writer);
            break;
        }


    }
};