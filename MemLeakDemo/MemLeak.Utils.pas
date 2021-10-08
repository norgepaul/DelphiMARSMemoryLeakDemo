unit MemLeak.Utils;

interface

uses
  System.Classes, System.SysUtils;

type
  TMemLeakUtils = class
    class function CreateStringList(const MaxSize: Integer = 1000000; const AddSingleString: Boolean = False): TStringList;
  end;

implementation

{ TMemLeakUtils }

class function TMemLeakUtils.CreateStringList(const MaxSize: Integer; const AddSingleString: Boolean): TStringList;
var
  i: Integer;
begin
  Result := TStringList.Create;

  if AddSingleString then
  begin
    Result.Text := StringOfChar('X', MaxSize - 1);
  end
  else
  begin
    for i := 1 to MaxSize div 2 do
    begin
      Result.Add('X');
    end;
  end;
end;

end.
