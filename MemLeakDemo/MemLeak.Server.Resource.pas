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
    The request generates a memory leak. It appears that the memory is never
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
    (* Function with memory leak                    *)
    (* --------------------------------------------- *)

    (* http://127.0.0.1:4000/rest/test/stringlist?size=1000000&singleline=true *)
    [GET, Path('/stringlist'), Produces(TMediaType.APPLICATION_JSON)]
    function TestStringList(
      [QueryParam('size')] const MaxSize: Integer;
      [QueryParam('singleline')] const SingleLine: Boolean): TJSONRawString;
  end;

implementation

{ TMemLeakResource }

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


initialization
  TMARSResourceRegistry.Instance.RegisterResource<TMemLeakResource>;

end.
