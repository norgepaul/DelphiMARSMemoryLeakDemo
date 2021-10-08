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
    The only requests that generates a memory leak are /rest/test/stringlist and
    /rest/test/stringlistobject. It appears that the memory is never
    de-allocated despite the calls to Free.

    This behaviour only occurs on Linux. Windows works as expected.

    If the singleline parameter is set to true, the memory leak is
    much smaller. The only difference is that with singleline, the characters
    are added a single line rather than each character being on a new line.
    The overall length of the texxt is the same however as new lines are included
    in the length.
  *)

  [Path('test')]
  [Produces(TMediaType.APPLICATION_JSON)]
  TMemLeakResource = class
  public
    (* --------------------------------------------- *)
    (* Functions with memory leak                    *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/stringlist *)
    [GET, Path('/stringlist'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringList(
      [QueryParam('size')] const MaxSize: Integer;
      [QueryParam('singleline')] const SingleLine: Boolean):TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/stringlistobject *)
    [GET, Path('/stringlistobject'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringListObject: TJSONRawString;


    (* --------------------------------------------- *)
    (* Functions without memory leak                 *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/getmem *)
    [GET, Path('/getmem'), Produces(TMediaType.APPLICATION_JSON)]
    function TestGetMemory: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/array *)
    [GET, Path('/array'), Produces(TMediaType.APPLICATION_JSON)]
    function TestArray: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/string *)
    [GET, Path('/string'), Produces(TMediaType.APPLICATION_JSON)]
    function TestString: TJSONRawString;

    (* http://127.0.0.1:4000/rest/test/object *)
    [GET, Path('/object'), Produces(TMediaType.APPLICATION_JSON)]
    function TestObject: TJSONRawString;
  end;

  TBigObj = class(TObject)
    S: String;
  end;

  TStringListObj = class(TObject)
  public
    procedure Go;
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

function TMemLeakResource.TestStringList(
  const MaxSize: Integer; const SingleLine: Boolean): TJSONRawString;
var
  S: TStringList;
  Size: Integer;
begin
  if MaxSize = 0 then
  begin
    Size := 1000000;
  end
  else
  begin
    Size := MaxSize;
  end;

  S := TMemLeakUtils.CreateStringList(Size, SingleLine);
  try
    sleep(2000);

    Result := format('{"length": %d}', [Length(S.Text)]);
  finally
    S.Free; // <-- This doesn't free the memory allocated by TStringList
  end;
end;

function TMemLeakResource.TestStringListObject: TJSONRawString;
var
  O: TStringListObj;
begin
  O := TStringListObj.Create;
  try
    O.Go;
  finally
    O.Free;
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

function TMemLeakResource.TestObject: TJSONRawString;
var
  O: TBigObj;
  i: Integer;
begin
  O := TBigObj.Create;
  try
    for i := 1 to Count do
    begin
      O.S := O.S + 'X';
    end;

    sleep(2000);
  finally
    O.Free;
  end;
end;

{ TStringListObj }

procedure TStringListObj.Go;
var
  S: TStringList;
begin
  S := TMemLeakUtils.CreateStringList;
  try
    sleep(2000);
  finally
    S.Free; // <-- This doesn't free the memory allocated by TStringList
  end;
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<TMemLeakResource>;

end.
