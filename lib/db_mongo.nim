#!strongSpaces

import times, oids, tables, sequtils, algorithm, mongo, bson

proc init* = mongo.init()
proc cleanup* = mongo.cleanup()

converter toBitfield[T:enum](e: set[T]): T =
  for x in e:
    result = cast[T](result.ord or x.ord)

type
  EMongo* = object of E_Base
  TBson* = object
    handle: ptr bson.TBson
    isOwner: bool
  TBsonCtorKind* = enum
    bckFloat64 = (1, "float64")
    bckUtf8 = (2, "UTF-8")
    bckDoc = (3, "Embedded document")
    bckArr = (4, "Array")
    bckBin = (5, "Binary")
    bckUndefined = (6, "Undefined (deprecated)")
    bckObjectId = (7, "ObjectId")
    bckBool = (8, "Bool")
    bckUtcDatetime = (9, "UTC datetime")
    bckNull = (0xa, "Null")
    bckRegex = (0xb, "Regular expression")
    bckDbPtr = (0xc, "DBPointer (deprecated)")
    bckJsCode = (0xd, "JavaScript code")
    bck0xe = (0xe, "Deprecated")
    bckJsCodeWithScope = (0xf, "JavaScript code w/ scope")
    bckInt32 = (0x10, "32-bit integer")
    bckTimestamp = (0x11, "Timestamp")
    bckInt64 = (0x12, "64-bit integer")
    bckMaxKey = (0x7f, "Max key")
    bckMinKey = (0xff, "Min key")
  TJsRegexOpt* = enum
    jroInsensitive = (0, "i")
    jroLocaleWordMatching = (1, "l")
    jroMultiline = (2, "m")
    jroDotAll = (3, "s")
    jroUnicodeWordMatching = (4, "u")
    jroVerbose = (5, "x")
  TBsonCtorDoc* = object
    vals*: TTable[string, TBsonCtor]
  TJsRegex* = tuple[pattern: string, opts: set[TJsRegexOpt]]
  TBsonCtor* = object
    case kind: TBsonCtorKind
    of bckUndefined, bckNull, bckMaxKey, bckMinKey:
      nil
    of bckFloat64:
      float64Val*: float64
    of bckUtf8:
      utf8*: string
    of bckDoc:
      doc*: ref TBsonCtorDoc
    of bckArr:
      arr*: seq[TBsonCtor]
    of bckBin:
      bin*: seq[uint8]
    of bckObjectId:
      oid*: bson.TOid
    of bckBool:
      boolVal*: bool
    of bckUtcDatetime:
      utcDatetime*: TTime
    of bckRegex:
      jsRegex*: tuple[pattern: string, opts: set[TJsRegexOpt]]
    of bckDbPtr:
      dbPtr*: tuple[coll: string, oid: bson.TOid]
    of bckJsCode:
      jsCode*: string
    of bck0xe:
      bck0xeStr*: string
    of bckJsCodeWithScope:
      JsCodeWithScope*: tuple[code, scope: string]
    of bckInt32:
      int32Val*: int32
    of bckTimestamp:
      timestampVal*: int64
    of bckInt64:
      int64Val*: int64
    else: # XXX: I don't know why this is needed.
      nil
  TBsonBinKind* {.size: int8.sizeof.} = enum
    bbkGeneric = (0, "Generic binary subtype")
    bbkFunction = (1, "Function")
    bbkBinaryOld = (2, "Binary (old)")
    bbkUuidOld = (3, "UUID (old)")
    bbkUuid = (4, "UUID")
    bbkMd5 = (5, "MD5")
    bbkUserDefined = (6, "User defined")

proc `$`*(opts: set[TJsRegexOpt]): string =
  result = ""
  for x in TJsRegexOpt:
    if x in opts:
      result.add $x

proc fail[T](x: varargs[T, `$`]) =
  var msg = ""
  for x in x:
    msg.add x

  raise newException(EMongo, msg)

proc `%`*(i: int32): TBsonCtor =
  result = TBsonCtor(kind: bckInt32, int32Val: i)

proc `%`*(i: int64): TBsonCtor =
  result = TBsonCtor(kind: bckInt64, int64Val: i)

proc `%`*(f: float64): TBsonCtor =
  result = TBsonCtor(kind: bckFloat64, float64Val: f)

proc `%`*(s: string): TBsonCtor =
  result = TBsonCtor(kind: bckUtf8, utf8: s)

proc `%`*(o: bson.TOid): TBsonCtor =
  result = TBsonCtor(kind: bckObjectId, oid: o)

proc `%`*(b: bool): TBsonCtor =
  result = TBsonCtor(kind: bckBool, boolVal: b)

proc `%`*(t: TTime): TBsonCtor =
  result = TBsonCtor(kind: bckUtcDatetime, utcDatetime: t)

proc `%`*(r: tuple[pattern: string, opts: set[TJsRegexOpt]]): TBsonCtor =
  result = TBsonCtor(kind: bckRegex, jsRegex: r)

proc `%`*(dbPtr: tuple[coll: string, oid: bson.TOid]): TBsonCtor =
  result = TBsonCtor(kind: bckDbPtr, dbPtr: dbPtr)

proc toBsonImpl(o: TBsonCtor, k: string, b: ptr bson.TBson) =
  let appendSucceeded = case o.kind
  of bckFloat64:
    bson.xappendDouble b, k, o.float64Val
  of bckUtf8:
    bson.xappendUtf8 b, k, o.utf8
  of bckDoc:
    var child = bson.new()
    var success = bson.xappendDocumentBegin(b, k, child)
    for childKey, childVal in o.doc.vals:
      var v = childVal
      toBsonImpl v, childKey, child

    if success:
      success = bson.appendDocumentEnd(b, child)
    success
  of bckArr:
    var child = bson.new()
    var success = bson.xappendArrayBegin(b, k, child)
    for i in 0 .. <o.arr.len:
      toBsonImpl o.arr[i], $i, child

    if success:
      success = bson.appendArrayEnd(b, child)
    success
  of bckBin:
    echo "TODO: specify bckBin subtype"
    var binVar = o.bin
    bson.xappendBinary(b, k, 0x0.TBinSubtype, cast[ptr uint8](binVar[0].addr),
      o.bin.len.uint32)
  of bckInt32:
    bson.xappendInt32 b, k, o.int32Val
  of bckInt64:
    bson.xappendInt64 b, k, o.int64Val
  of bckRegex:
    bson.xappendRegex b, k, o.jsRegex.pattern, $o.jsRegex.opts
  of bckBool:
    bson.xappendBool b, k, o.boolVal
  else:
    echo "unhandled BSON ctor type: ", o.kind
    quit 1
    false

  if not appendSucceeded:
    fail "not enough space to append"

proc `%`*(fields: openarray[tuple[k: string, v: TBsonCtor]]): TBsonCtor =
  var b = new(TBsonCtorDoc)
  b[] = TBsonCtorDoc(vals: initTable[string, TBsonCtor]())
  for x in fields:
    b.vals[x[0]] = x[1]
  result = TBsonCtor(kind: bckDoc, doc: b)

proc `%`*[T](arr: array[T, TBsonCtor]): TBsonCtor =
  var s = newSeq[arr[0].type](arr.len)
  for i, x in arr:
    s[i] = x
  result = TBsonCtor(kind: bckArr, arr: s)

proc isOwner*(o: TBson): bool =
  o.isOwner

proc newBson*(handle: ptr bson.TBson, isOwner: bool): ref TBson =
  new(result) do(o: ref TBson):
    if o.isOwner:
      bson.destroy(o.handle)

  result[] = TBson(handle: handle, isOwner: isOwner)

proc newBson*(): ref TBson =
  var handle = bson.new()
  init(handle[])
  newBson(handle, true)

converter toBson*(o: TBsonCtor): ref TBson =
  assert o.kind == bckDoc, "Invalid top-level BSON type."
  var b = bson.new()
  for k, v in o.doc.vals:
    toBsonImpl(v, k, b)

  newBson(b, isOwner = true)

type
  TWriteConcernAck* = enum
    wcatMajority = -1
    wcatOff
    wcatOn

proc newWriteConcern*(journalling = true,
        writeConcernAck: TWriteConcernAck|range[2 .. 1000] = wcatOn,
        wTimeout = 0.Natural,
        fsync = false): TWriteConcern =
  result = mongo.write_concern_new()
  mongo.write_concern_set_fsync(result, fsync)
  mongo.write_concern_set_journal(result, journalling)
  mongo.write_concern_set_w(result, writeConcernAck.int32)

type
  TClient* = object
    handle: mongo.TClient
    defaultColl: TCollection

converter toHandle(o: var TClient): mongo.TClient = o.handle

proc `writeConcern=`*(o: var TClient, val: TWriteConcern) =
  client_set_write_concern(o, val)

proc getColl(o: var TClient, coll: tuple[db, coll: string]):
        mongo.TCollection =
  if coll == (nil, nil):
    assert o.defaultColl.pointer != nil
    o.defaultColl
  else:
    mongo.clientGetCollection(o, coll.db, coll.coll)

proc initClient*(
        o: var TClient,
        uri: string = "mongodb://127.0.0.1",
        defaultColl: tuple[db, coll: string] = (nil, nil),
        writeConcern = newWriteConcern(writeConcernAck = wcatOn)) = # XXX: writeConcernAck cannot be omitted.
  o = TClient(handle: mongo.client_new(uri))
  if o.handle.pointer == nil:
    fail "Invalid MongoDB URI: ", uri

  o.writeConcern = writeConcern
  if defaultColl != (nil, nil):
    o.defaultColl = o.getColl(defaultColl)

proc destruct*(o: var TClient) = # XXX: generates invalid code: {.destructor.} =
  mongo.clientDestroy(o)

proc jsRegexOpts*(o: TBsonVal): set[TJsRegexOpt] =
  assert o.kind == bkJsRegex
  for x in o.jsRegex.opts:
    for y in TJsRegexOpt:
      if x == ($y)[0]:
        result.incl y

proc update*(o: var TClient,
      selector, update: ref TBson,
      flags: set[TUpdateFlags] = {},
      writeConcern = nil.TWriteConcern,
      coll: tuple[db, coll: string] = (nil, nil)) =
  var error: bson.TError
  if not mongo.collectionUpdate(o.getColl(coll), flags, selector.handle,
          update.handle, writeConcern, addr error):
    fail error

# TODO: Read prefs argument.
proc count*(o: var TClient,
        query = newBson(),
        flags: set[TQueryFlags] = {},
        skip, limit = 0.Natural,
        coll: tuple[db, coll: string] = (nil, nil)): Natural =
  var c = o.getColl(coll)
  var error: bson.TError
  var n = mongo.collection_count(c, flags, query.handle,
    skip.int64, limit.int64, nil.TReadPrefs, addr error)
  if n == -1:
    fail error
  result = n

# TODO: # bulk remove.
proc remove*(o: var TClient,
      selector = newBson(),
      flags: set[TRemoveFlags] = {},
      writeConcern = nil.TWriteConcern,
      coll: tuple[db, coll: string] = (nil, nil)) =
  # TODO: write concern
  var error: bson.TError
  if not mongo.collectionRemove(o.getColl(coll), flags,
          selector.handle, writeConcern, addr error):
    fail error

iterator find*(o: var TClient,
        query = newBson(),
        fields = newBson(),
        flags: set[TQueryFlags] = {},
        skip, limit, batchSize = 0.Natural,
        coll: tuple[db, coll: string] = (nil, nil)): ref TBson =
  # TODO: not needed because of the converter, and maybe the presence of it
  # causes invalid C code to be generated; report it.
  when false:
    var queryFlagsInt: cint
    for x in flags:
      queryFlagsInt = queryFlagsInt or x.cint

  # TODO: read prefs.
  # TODO: needs to be freed with mongoc_collection_destroy.
  var cursor = mongo.collectionFind(
        o.getColl(coll),
        flags,
        skip.uint32,
        limit.uint32,
        batchSize.uint32,
        query.handle,
        fields.handle,
        nil.TReadPrefs)
  assert cursor.pointer != nil, "Invalid API usage"
  var doc: ptr bson.TBson

  var error: bson.TError
  while true:
    if mongo.cursor_error(cursor, addr error):
      fail error

    if mongo.cursor_more(cursor) and
          mongo.cursor_next(cursor, cast[ptr ptr bson.TBson](addr doc)):
      yield newBson(doc, isOwner = false)
    else:
      break

  when false: # This crashes.
    bson.destroy(doc)

# TODO: bulk insert.
proc insert*(
        o: var TClient,
        doc: ref TBson,
        flags: set[TInsertFlags] = {},
        writeConcern = nil.TWriteConcern,
        coll: tuple[db, coll: string] = (nil, nil)) =
  var error: bson.TError
  if not mongo.collection_insert(o.getColl(coll), flags, doc.handle,
        writeConcern, addr error):
    fail error

iterator arrIndices*(o: ptr bson.TIter):
        tuple[idx: int, v: ptr bson.TBsonVal, iter: ptr bson.TIter] =
  assert bson.iter_type(o[]) == bkArr

  var
    len: uint32
    data: ptr uint8
    b: bson.TBson
  bson.iter_array o[], len, addr data
  if not bson.init_static(b, data[], len):
    fail "Unable to initialise BSON"

  var
    iter: bson.TIter
    idx = 0
  if not bson.iter_init(iter, b):
    fail "unable to initialise iterator"

  while bson.iter_next(iter):
    var
      val = bson.iter_value(iter)
      key = bson.iter_key(iter)
    if val == nil:
      fail "unable to get BSON value"

    if key == nil:
      fail "unable to get BSON key"

    yield (idx, val, addr iter)
    inc idx

iterator fields*(o: ptr bson.TIter):
        tuple[k: string, v: ptr bson.TBsonVal, iter: ptr bson.TIter] =
  assert bson.iter_type(o[]) == bkDoc

  var len: uint32
  var data: ptr uint8
  bson.iter_document o[], len, addr data
  var b: bson.TBson
  if not bson.init_static(b, data[], len):
    fail "Unable to initialise BSON"

  var iter: bson.TIter
  if not bson.iter_init(iter, b):
    fail "unable to initialise iterator"

  while bson.iter_next(iter):
    var val = bson.iter_value(iter)
    if val == nil:
      fail "unable to get BSON value"

    var key = bson.iter_key(iter)
    if key == nil:
      fail "unable to get BSON key"

    yield ($key, val, addr iter)

iterator fields*(o: ref TBson):
        tuple[k: string, v: ptr bson.TBsonVal, iter: ptr bson.TIter] =
  var iter: bson.TIter
  if not bson.iter_init(iter, o.handle[]):
    fail "unable to initialise iterator"

  while bson.iter_next(iter):
    var val = bson.iter_value(iter)
    if val == nil:
      fail "unable to get BSON value"

    var key = bson.iter_key(iter)
    if key == nil:
      fail "unable to get BSON key"

    yield ($key, val, addr iter)
