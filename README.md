# DelphiMARSMemoryLeakDemo
Demonstrates a  memory leak when running MARS on Linux. Tested with Delphi 10.4.2.

Try the MemLeakDemo console app on both Windows and Linux. Windows works as expected, but the MARS endpoint - http://127.0.0.1:4000/rest/test/stringlist - on Linux causes a big memory leak.
