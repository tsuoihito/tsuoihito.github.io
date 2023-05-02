---
title: "手動インストールしたOpenJDKのバイナリとjarファイルを関連付ける"
date: 2023-04-17T23:03:41+09:00
draft: false
tags: [ java, windows, openjdk ]
---

WindowsでのJDK/JREのインストールはOracle JDKを使っている人が多いと思いますが、オープンソース好きな私としてはOpenJDKを使いたい気持ちがあります。
ただOpenJDKは[Oracleなどがビルドしたバイナリ](https://jdk.java.net/)が置いてあるだけでOracle JDKのようにインストーラが付属しているわけではないので、エクスプローラーなどでjarファイルをダブルクリックで実行したい場合は、OpenJDKのバイナリとjarファイルの関連付けを手動で行う必要があります。

追記: [Eclipse Adoptium](https://adoptium.net/)ではインストーラが配布されており、jarファイルとの関連付けも行えるようです。

## レジストリをいじる

1. レジストリエディタで `HEKY_CLASSES_ROOT\.jar` エントリに `jarfile` を設定する。
2. `HEKY_CLASSES_ROOT\jarfile` エントリにファイルタイプ名 (`Executable Jar File` とか) を設定する。
3. `HKEY_CLASSES_ROOT\jarfile\DefaultIcon` エントリにJavaバイナリのパス (今回は `%JAVA_HOME%\bin\javaw.exe`) を設定する。
4. `HEKY_CLASSES_ROOT\jarfile\shell\open\command` に実行コマンドを設定するのだが、このエントリはデフォルトのデータタイプの `REG_SZ` だと環境変数が展開されないので、 `JAVA_HOME` などの環境変数を使う場合はデータタイプを `REG_EXPAND_SZ` にする必要がある。しかしこのタイプの既定値はレジストリエディタでは作成できないため、`reg add HKCR\jarfile\shell\open\command /t REG_EXPAND_SZ` コマンドを使って空の `REG_EXPAND_SZ` タイプの値を作成する。このときコマンドの実行結果は開いているレジストリエディタには自動反映されないので、一度エディタを再起動する必要がある。
5. 4で作成した `command` エントリに実行コマンド (今回は `%JAVA_HOME%\bin\javaw.exe -jar "%1" %*`) を設定する。

## 最終形

``` txt
HKEY_CLASSES_ROOT
  .jar
    (Default) = jarfile
  jarfile
    (Default) = Executable Jar File
    DefaultIcon
       (Default) = %JAVA_HOME%\bin\javaw.exe
    shell
      open
        command
          (Default) = %JAVA_HOME%\bin\javaw.exe -jar "%1" %*
```

## 備考

- エクスプローラーでのファイルタイプ表示はタスクマネージャーでエクスプローラーを再起動すると反映する。
- 実行コマンドに環境変数を使わない場合はデフォルトの `REG_SZ` タイプで大丈夫。
- `DefaultIcon` エントリは `REG_SZ` タイプでも環境変数は展開される模様。
- `DefaultIcon` エントリを設定しない場合、`command` エントリに設定した実行ファイルのアイコンが使われる。

## 参考

- [windows xp - How can I specify REG_EXPAND_SZ entries in a .REG file? - Super User](https://superuser.com/questions/251794/how-can-i-specify-reg-expand-sz-entries-in-a-reg-file)
- [reg add | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add)
