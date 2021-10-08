unit MemLeak.Server.Resource;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Hash, System.DateUtils,
  System.IOUtils, System.Variants, System.Classes,

  Web.HTTPApp,

  MARS.Core.Attributes, MARS.Core.Registry, MARS.Core.JSON, MARS.Core.MediaType,

  MemLeak.Utils;

type
  (*
    The only request that generates a memory leak is /rest/test/stringlist.
    It appears that the memory is never de-allocated despite the call to Free.

    This behaviour only occurs on Linux. Windows works as expected.
  *)

  [Path('test')]
  [Produces(TMediaType.APPLICATION_JSON)]
  TMemLeakResource = class
  public
    (* http://127.0.0.1:4000/rest/test/stringlist *)
    [GET, Path('/stringlist'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringList: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/getmem *)
    [GET, Path('/getmem'), Produces(TMediaType.APPLICATION_JSON)]
    function TestGetMemory: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/array *)
    [GET, Path('/array'), Produces(TMediaType.APPLICATION_JSON)]
    function TestArray: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/string *)
    [GET, Path('/string'), Produces(TMediaType.APPLICATION_JSON)]
    function TestString: TJSONRawString;
  end;

implementation

const
  COUNT = 100000000;

{ TMemLeakResource }

function TMemLeakResource.TestString: TJSONRawString;
var
  S: String;
begin
  S := StringOfChar('X', COUNT);

  sleep(2000);

  Result := '{}';
end;

function TMemLeakResource.TestStringList: TJSONRawString;
var
  S: TStringList;
begin
  S := TMemLeakUtils.CreateStringList;
  try
    sleep(2000);
  finally
    S.Free;
  end;

  Result := '{}';
end;

function TMemLeakResource.TestArray: TJSONRawString;
var
  A: TArray<Byte>;
  i: Integer;
begin
  SetLength(A, COUNT);

  for i := Low(A) to High(A) do
  begin
    A[i] := $AA;
  end;

  sleep(2000);

  Result := '{}';
end;

function TMemLeakResource.TestGetMemory: TJSONRawString;
type
  TBigRec = record
    S: String;
  end;
  PBigRec = ^TBigRec;
var
  P: PBigRec;
begin
  P := new(PBigRec);
  P.S := StringOfChar('X', COUNT);

  sleep(2000);

  Dispose(P);

  Result := '{}';
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<TMemLeakResource>;

end.
