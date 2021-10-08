unit MemLeak.Utils;

interface

uses
  System.Classes;

type
  TMemLeakUtils = class
    class function CreateStringList(const Count: Integer = 1000000; const Value: String = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'): TStringList;
  end;

implementation

{ TMemLeakUtils }

class function TMemLeakUtils.CreateStringList(const Count: Integer; const Value: String): TStringList;
var
  i: Integer;
begin
  Result := TStringList.Create;

  for i := 1 to Count do
  begin
    Result.Add(Value);
  end;
end;

end.
