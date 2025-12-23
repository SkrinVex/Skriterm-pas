program SkriTerm;
{ SkriTerm — простая оболочка.
  - Встроенные команды работают через ;
  - Система истории
  - Для выполнения кастомной команды требуется выполнять программу от прав администратора (sudo)
  - Разработчик: SkrinVex
  - Работает только на системах на основе Linux
}

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Process, Crt;

const
  HISTORY_FILENAME = '.skriterm_history';
  MAX_HISTORY_SIZE = 1000; // Максимальное количество команд в истории
  APP_NAME = 'SkriTerm';
  APP_VERSION = '1.2';
  APP_AUTHOR = 'SkrinVex';

var
  History: TStringList;
  HomeDir: string;
  PromptUser: string;

procedure Init;
var
  histPath: string;
begin
  HomeDir := GetEnvironmentVariable('HOME');
  if HomeDir = '' then HomeDir := '.';
  History := TStringList.Create;
  History.Duplicates := dupIgnore;
  histPath := IncludeTrailingPathDelimiter(HomeDir) + HISTORY_FILENAME;
  if FileExists(histPath) then
    try
      History.LoadFromFile(histPath);
      // Удаляем пустые строки из истории
      while History.IndexOf('') >= 0 do
        History.Delete(History.IndexOf(''));
    except
      // ignore
    end;
  PromptUser := GetEnvironmentVariable('USER');
  if PromptUser = '' then PromptUser := 'user';
end;

procedure SaveHistoryToDefault;
var
  path: string;
  tempList: TStringList;
  i, startIdx: Integer;
begin
  path := IncludeTrailingPathDelimiter(HomeDir) + HISTORY_FILENAME;
  try
    if History.Count > MAX_HISTORY_SIZE then
    begin
      tempList := TStringList.Create;
      try
        startIdx := History.Count - MAX_HISTORY_SIZE;
        for i := startIdx to History.Count - 1 do
          tempList.Add(History[i]);
        History.Assign(tempList);
      finally
        tempList.Free;
      end;
    end;
    History.SaveToFile(path);
  except
    // ignore
  end;
end;

procedure ShowAbout;
begin
  Writeln(APP_NAME, ' ', APP_VERSION);
  Writeln('Разработчик: ', APP_AUTHOR);
  Writeln('Самая простая оболочка');
end;

procedure ShowHelp;
begin
  Writeln('Встроенные команды:');
  Writeln('  :help               - показать справку');
  Writeln('  :about              - информация об оболочке');
  Writeln('  :exit               - выйти');
  Writeln('  :clear              - очистить экран');
  Writeln('  :pwd                - показать текущую директорию');
  Writeln('  :ls [path]          - показать содержимое директории');
  Writeln('  :cd [dir]           - перейти в директорию');
  Writeln('  :cat <file>         - показать текстовый файл');
  Writeln('  :touch <file>       - создать/обновить файл');
  Writeln('  :rm <path>          - удалить файл или директорию');
  Writeln('  :mkdir <dir>        - создать директорию');
  Writeln('  :whoami             - показать пользователя');
  Writeln('  :history [n]        - показать последние n команд (по умолчанию все)');
  Writeln('  :clearhist          - очистить историю команд');
  Writeln('  :!n                 - выполнить n-ю команду из истории');
  Writeln('  :savehist [file]    - сохранить историю');
  Writeln('  :loadhist [file]    - загрузить историю');
  Writeln('  :sudo <command>     - выполнить команду через sudo');
  Writeln('');
  Writeln('Навигация: стрелки вверх/вниз - история, влево/вправо - курсор');
end;

procedure DoClear;
begin
  ClrScr;
end;

procedure ShowPwd;
begin
  Writeln(GetCurrentDir);
end;

function AttrsToStr(Attr: Integer): string;
begin
  Result := '';
  if (Attr and faDirectory) <> 0 then Result := Result + 'D';
  if (Attr and faReadOnly) <> 0 then
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + 'RO';
  end;
  if (Attr and faHidden) <> 0 then
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + 'H';
  end;
  if Result = '' then Result := '-';
end;

procedure PrintLsHeader;
begin
  Writeln(Format('%-16s  %10s  %-8s  %s', ['Дата/Время', 'Размер', 'Атрибуты', 'Имя']));
  Writeln(StringOfChar('-', 70));
end;

procedure DoLs(arg: string);
var
  path, full: string;
  SR: TSearchRec;
  res: Integer;
  dtStr, sizeStr, attrs: string;
  fnFull: string;
begin
  path := Trim(arg);
  if path = '' then path := GetCurrentDir;
  if (Copy(path,1,2) = '~/') or (path = '~') then
    path := IncludeTrailingPathDelimiter(HomeDir) + Copy(path, 3, MaxInt);
  full := ExpandFileName(path);
  if not DirectoryExists(full) then
  begin
    Writeln('Директория не найдена: ', full);
    Exit;
  end;
  PrintLsHeader;
  res := FindFirst(IncludeTrailingPathDelimiter(full) + '*', faAnyFile, SR);
  try
    while res = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        fnFull := IncludeTrailingPathDelimiter(full) + SR.Name;
        if FileAge(fnFull) <> -1 then
          dtStr := FormatDateTime('yyyy-mm-dd hh:nn', FileDateToDateTime(FileAge(fnFull)))
        else
          dtStr := '----';
        if (SR.Attr and faDirectory) <> 0 then
          sizeStr := '<DIR>'
        else
          sizeStr := IntToStr(SR.Size);
        attrs := AttrsToStr(SR.Attr);
        Writeln(Format('%-16s  %10s  %-8s  %s', [dtStr, sizeStr, attrs, SR.Name]));
      end;
      res := FindNext(SR);
    end;
  finally
    FindClose(SR);
  end;
end;

procedure DoCat(arg: string);
var
  fn: string;
  F: TextFile;
  line: string;
begin
  fn := Trim(arg);
  if fn = '' then
  begin
    Writeln('Использование: :cat <файл>');
    Exit;
  end;
  if not FileExists(fn) then
  begin
    Writeln('Файл не найден: ', fn);
    Exit;
  end;
  try
    AssignFile(F, fn);
    Reset(F);
    try
      while not Eof(F) do
      begin
        ReadLn(F, line);
        Writeln(line);
      end;
    finally
      CloseFile(F);
    end;
  except
    on E: Exception do
      Writeln('Ошибка при чтении ', fn, ' : ', E.Message);
  end;
end;

procedure DoTouch(arg: string);
var
  fn: string;
begin
  fn := Trim(arg);
  if fn = '' then
  begin
    Writeln('Использование: :touch <файл>');
    Exit;
  end;
  try
    if FileExists(fn) then
      FileSetDate(fn, DateTimeToFileDate(Now))
    else
    begin
      with TStringList.Create do
        try
          SaveToFile(fn);
        finally
          Free;
        end;
    end;
  except
    on E: Exception do
      Writeln('Не удалось создать/обновить файл: ', fn, ' : ', E.Message);
  end;
end;

function DeletePathRecursive(const Path: string): Boolean;
var
  SR: TSearchRec;
  res: Integer;
  Full: string;
begin
  Result := False;
  if FileExists(Path) then
  begin
    Result := DeleteFile(Path);
    Exit;
  end;
  if DirectoryExists(Path) then
  begin
    res := FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, SR);
    try
      while res = 0 do
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          Full := IncludeTrailingPathDelimiter(Path) + SR.Name;
          if (SR.Attr and faDirectory) <> 0 then
          begin
            if not DeletePathRecursive(Full) then Exit(False);
          end
          else
          begin
            if not DeleteFile(Full) then Exit(False);
          end;
        end;
        res := FindNext(SR);
      end;
    finally
      FindClose(SR);
    end;
    Result := RemoveDir(Path);
  end
  else
    Result := False;
end;

procedure DoRm(arg: string);
var
  p: string;
begin
  p := Trim(arg);
  if p = '' then
  begin
    Writeln('Использование: :rm <путь>');
    Exit;
  end;
  p := ExpandFileName(p);
  if not FileExists(p) and not DirectoryExists(p) then
  begin
    Writeln('Путь не найден: ', p);
    Exit;
  end;
  if DeletePathRecursive(p) then
    Writeln('Удалено: ', p)
  else
    Writeln('Не удалось удалить: ', p);
end;

procedure DoMkdir(arg: string);
var
  dn: string;
begin
  dn := Trim(arg);
  if dn = '' then
  begin
    Writeln('Использование: :mkdir <директория>');
    Exit;
  end;
  dn := ExpandFileName(dn);
  if DirectoryExists(dn) then
    Writeln('Директория уже существует: ', dn)
  else
  begin
    if CreateDir(dn) then
      Writeln('Создано: ', dn)
    else
      Writeln('Не удалось создать: ', dn);
  end;
end;

procedure DoCd(arg: string);
var
  target: string;
begin
  target := Trim(arg);
  if target = '' then target := HomeDir;
  if (Copy(target,1,2) = '~/') or (target = '~') then
    target := IncludeTrailingPathDelimiter(HomeDir) + Copy(target, 3, MaxInt);
  try
    target := ExpandFileName(target);
    if DirectoryExists(target) then
    begin
      try
        ChDir(target);
      except
        on E: Exception do
          Writeln('Не удалось перейти в директорию ', target, ' : ', E.Message);
      end;
    end
    else
      Writeln('Директория не найдена: ', target);
  except
    on E: Exception do
      Writeln('Ошибка: ', E.Message);
  end;
end;

procedure DoWhoami;
var
  u: string;
begin
  u := GetEnvironmentVariable('USER');
  if u = '' then u := PromptUser;
  Writeln(u);
end;

procedure ShowHistory(arg: string);
var
  i, n, startIdx: Integer;
  limitStr: string;
begin
  limitStr := Trim(arg);
  if limitStr = '' then
    n := History.Count
  else if not TryStrToInt(limitStr, n) then
  begin
    Writeln('Использование: :history [количество]');
    Exit;
  end;

  if History.Count = 0 then
  begin
    Writeln('История пуста');
    Exit;
  end;

  if n > History.Count then n := History.Count;
  startIdx := History.Count - n;
  
  for i := startIdx to History.Count - 1 do
    Writeln(Format('%4d  %s', [i+1, History[i]]));
  
  Writeln;
  Writeln('Всего команд в истории: ', History.Count);
end;

procedure ClearHistory;
begin
  History.Clear;
  SaveHistoryToDefault;
  Writeln('История команд очищена');
end;

procedure LoadHistoryFromFile(fn: string);
var
  path: string;
begin
  if Trim(fn) = '' then
    path := IncludeTrailingPathDelimiter(HomeDir) + HISTORY_FILENAME
  else
    path := fn;
  if FileExists(path) then
  begin
    try
      History.LoadFromFile(path);
      // Удаляем пустые строки
      while History.IndexOf('') >= 0 do
        History.Delete(History.IndexOf(''));
      Writeln('История загружена из ', path, ' (', History.Count, ' команд)');
    except
      on E: Exception do
        Writeln('Не удалось загрузить историю: ', E.Message);
    end;
  end
  else
    Writeln('Файл не найден: ', path);
end;

procedure SaveHistoryToFile(fn: string);
var
  path: string;
begin
  if Trim(fn) = '' then
    path := IncludeTrailingPathDelimiter(HomeDir) + HISTORY_FILENAME
  else
    path := fn;
  try
    History.SaveToFile(path);
    Writeln('История сохранена в ', path, ' (', History.Count, ' команд)');
  except
    on E: Exception do
      Writeln('Не удалось сохранить историю: ', E.Message);
  end;
end;

procedure RunSudoInteractive(cmdline: string);
var
  P: TProcess;
  shellCmd: string;
begin
  if Trim(cmdline) = '' then
  begin
    Writeln('Использование: :sudo <команда>');
    Exit;
  end;
  shellCmd := 'sudo ' + cmdline;
  P := TProcess.Create(nil);
  try
    P.Executable := '/bin/sh';
    P.Parameters.Clear;
    P.Parameters.Add('-c');
    P.Parameters.Add(shellCmd);
    P.Options := [poWaitOnExit];
    try
      P.Execute;
      P.WaitOnExit;
    except
      on E: Exception do
        Writeln('Не удалось запустить sudo: ', E.Message);
    end;
  finally
    P.Free;
  end;
end;

procedure ProcessLine(line: string); forward;

procedure ExecuteFromHistoryIndexCall(idx: Integer);
begin
  if (idx < 1) or (idx > History.Count) then
  begin
    Writeln('Индекс истории вне диапазона (1-', History.Count, ')');
    Exit;
  end;
  Writeln('Выполнение: ', History[idx-1]);
  ProcessLine(History[idx-1]);
end;

procedure ProcessLine(line: string);
var
  t, cmd, rest: string;
  p, n: Integer;
begin
  t := Trim(line);
  if t = '' then Exit;
  
  if (History.Count = 0) or (History[History.Count-1] <> t) then
    History.Add(t);

  if (Length(t) > 2) and (t[1] = ':') and (t[2] = '!') then
  begin
    rest := Trim(Copy(t, 3, MaxInt));
    if TryStrToInt(rest, n) then
      ExecuteFromHistoryIndexCall(n)
    else
      Writeln('Использование: :!<номер>');
    Exit;
  end;

  if (Length(t) >= 1) and (t[1] = ':') then
  begin
    p := Pos(' ', t);
    if p = 0 then
    begin
      cmd := Copy(t, 2, MaxInt);
      rest := '';
    end
    else
    begin
      cmd := Copy(t, 2, p-2);
      rest := Trim(Copy(t, p+1, MaxInt));
    end;

    if cmd = 'help' then ShowHelp
    else if cmd = 'about' then ShowAbout
    else if cmd = 'exit' then
    begin
      SaveHistoryToDefault;
      Halt(0);
    end
    else if cmd = 'clear' then DoClear
    else if cmd = 'pwd' then ShowPwd
    else if cmd = 'ls' then DoLs(rest)
    else if cmd = 'cd' then DoCd(rest)
    else if cmd = 'cat' then DoCat(rest)
    else if cmd = 'touch' then DoTouch(rest)
    else if cmd = 'rm' then DoRm(rest)
    else if cmd = 'mkdir' then DoMkdir(rest)
    else if cmd = 'whoami' then DoWhoami
    else if cmd = 'history' then ShowHistory(rest)
    else if cmd = 'clearhist' then ClearHistory
    else if cmd = 'savehist' then SaveHistoryToFile(rest)
    else if cmd = 'loadhist' then LoadHistoryFromFile(rest)
    else if cmd = 'sudo' then RunSudoInteractive(rest)
    else
      Writeln('Неизвестная команда: ', cmd, '. Введите :help для списка.');
  end
  else
  begin
    Writeln('Внешние команды отключены. Используйте команды с ":"');
  end;
end;

function BuildPrompt: string;
var
  user, host, cwd: string;
  shortCwd: string;
begin
  user := GetEnvironmentVariable('USER');
  if user = '' then user := PromptUser;
  host := GetEnvironmentVariable('HOSTNAME');
  if host = '' then host := 'localhost';
  cwd := GetCurrentDir;
  shortCwd := cwd;
  if Length(shortCwd) > 40 then
    shortCwd := '...' + Copy(shortCwd, Length(shortCwd)-37+1, 37);
  Result := Format('%s@%s:%s> ', [user, host, shortCwd]);
end;

function ReadLineWithHistory(const Prompt: string): string;
var
  buf: array of Char;
  s: string;
  ch: Char;
  i, curPos, lenBuf: Integer;
  seq: String;
  histPos: Integer;
  tempInput: string;
  
  procedure RedrawLine;
  var
    j, tail: Integer;
  begin
    Write(#13, #27'[K');
    Write(Prompt);
    if lenBuf > 0 then
      for j := 0 to lenBuf-1 do Write(buf[j]);
    tail := lenBuf - curPos;
    for j := 1 to tail do Write(#8);
    Flush(Output);
  end;
  
begin
  SetLength(buf, 0);
  lenBuf := 0;
  curPos := 0;
  histPos := History.Count; // Начинаем с конца истории
  tempInput := '';
  
  Write(Prompt);
  Flush(Output);
  
  while True do
  begin
    ch := ReadKey;
    
    if ch = #13 then // Enter
    begin
      Writeln;
      if lenBuf = 0 then 
        Result := ''
      else
      begin
        SetString(s, PChar(@buf[0]), lenBuf);
        Result := s;
      end;
      Exit;
    end
    else if (ch = #8) or (ch = #127) then // Backspace
    begin
      if curPos > 0 then
      begin
        for i := curPos-1 to lenBuf-2 do
          buf[i] := buf[i+1];
        Dec(lenBuf);
        Dec(curPos);
        RedrawLine;
      end;
    end
    else if ch = #0 then // Extended key
    begin
      ch := ReadKey;
      case Ord(ch) of
        72: // UP arrow
          begin
            if History.Count > 0 then
            begin
              if histPos = History.Count then
              begin
                // Сохраняем текущий ввод
                SetString(tempInput, PChar(@buf[0]), lenBuf);
              end;
              if histPos > 0 then
              begin
                Dec(histPos);
                s := History[histPos];
                SetLength(buf, Length(s));
                for i := 1 to Length(s) do buf[i-1] := s[i];
                lenBuf := Length(s);
                curPos := lenBuf;
                RedrawLine;
              end;
            end;
          end;
        80: // DOWN arrow
          begin
            if History.Count > 0 then
            begin
              if histPos < History.Count - 1 then
              begin
                Inc(histPos);
                s := History[histPos];
              end
              else
              begin
                histPos := History.Count;
                s := tempInput;
              end;
              SetLength(buf, Length(s));
              for i := 1 to Length(s) do buf[i-1] := s[i];
              lenBuf := Length(s);
              curPos := lenBuf;
              RedrawLine;
            end;
          end;
        77: // RIGHT arrow
          if curPos < lenBuf then
          begin
            Write(buf[curPos]);
            Inc(curPos);
            Flush(Output);
          end;
        75: // LEFT arrow
          if curPos > 0 then
          begin
            Write(#8);
            Dec(curPos);
            Flush(Output);
          end;
      end;
    end
    else if ch = #27 then // ESC - ANSI sequences (Linux)
    begin
      seq := '';
      if KeyPressed then seq := seq + ReadKey;
      if KeyPressed then seq := seq + ReadKey;
      
      if (Length(seq) >= 2) and (seq[1] = '[') then
      begin
        case seq[2] of
          'A': // UP
            begin
              if History.Count > 0 then
              begin
                if histPos = History.Count then
                begin
                  // Сохраняем текущий ввод
                  SetString(tempInput, PChar(@buf[0]), lenBuf);
                end;
                if histPos > 0 then
                begin
                  Dec(histPos);
                  s := History[histPos];
                  SetLength(buf, Length(s));
                  for i := 1 to Length(s) do buf[i-1] := s[i];
                  lenBuf := Length(s);
                  curPos := lenBuf;
                  RedrawLine;
                end;
              end;
            end;
          'B': // DOWN
            begin
              if History.Count > 0 then
              begin
                if histPos < History.Count - 1 then
                begin
                  Inc(histPos);
                  s := History[histPos];
                end
                else
                begin
                  histPos := History.Count;
                  s := tempInput;
                end;
                SetLength(buf, Length(s));
                for i := 1 to Length(s) do buf[i-1] := s[i];
                lenBuf := Length(s);
                curPos := lenBuf;
                RedrawLine;
              end;
            end;
          'C': // RIGHT
            if curPos < lenBuf then
            begin
              Write(buf[curPos]);
              Inc(curPos);
              Flush(Output);
            end;
          'D': // LEFT
            if curPos > 0 then
            begin
              Write(#8);
              Dec(curPos);
              Flush(Output);
            end;
        end;
      end;
    end
    else if ch >= ' ' then
    begin
      SetLength(buf, lenBuf+1);
      for i := lenBuf downto curPos+1 do buf[i] := buf[i-1];
      buf[curPos] := ch;
      Inc(lenBuf);
      Inc(curPos);
      RedrawLine;
    end;
  end;
end;

procedure MainLoop;
var
  line, prompt: string;
begin
  Writeln('================================================================');
  Writeln('  ', APP_NAME, ' v', APP_VERSION, ' - Простая оболочка');
  Writeln('================================================================');
  Writeln;
  Writeln('Введите :help для справки');
  if History.Count > 0 then
    Writeln('Загружено команд из истории: ', History.Count);
  Writeln;
  
  while True do
  begin
    try
      prompt := BuildPrompt;
      line := ReadLineWithHistory(prompt);
    except
      Writeln;
      Break;
    end;
    if Trim(line) <> '' then
      ProcessLine(line);
  end;
end;

procedure FinalizeApp;
begin
  try
    SaveHistoryToDefault;
  finally
    History.Free;
  end;
end;

begin
  Init;
  try
    MainLoop;
  finally
    FinalizeApp;
  end;
end.
