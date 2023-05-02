---
title: "Firefoxのサイドタブをいい感じに設定する"
date: 2023-04-17T19:41:19+09:00
draft: false
tags: [ firefox ]
---

いつも新しいPCにFirefoxをインストールするたびにタブの位置を左サイドバーにする設定をしているんですが、この前Windows 11でのセットアップでつまづいたところがあったのでメモ。

## 環境

- Windows 11 Home
- Firefox 111.0.1

## 手順

### アドオンのインストール

[タブをサイドバーを表示するアドオン](https://addons.mozilla.org/ja/firefox/addon/tree-style-tab/)をインストールする。

### Firefoxの見た目を変えられるように設定を変更

以前はFirefoxの設定は特にいじらなくても見た目 (上部タブバーとか) を変えられた気がするんですが、仕様が変わったみたいです。

`about:config` ページにアクセスし、以下の項目を全て `true` にする。

- `toolkit.legacyUserProfileCustomizations.stylesheets`
- `layers.acceleration.force-enabled`
- `gfx.webrender.all`
- `gfx.webrender.enabled`
- `layout.css.backdrop-filter.enabled`
- `svg.context-properties.content.enabled`

### 上部タブバーとサイドバーのヘッダーを削除

`%APPDATA%\Mozilla\Firefox\Profiles\xxxxxxxx.default-release\` 配下に `chrome` フォルダを作成し、
その中に `userChrome.css` ファイルを下記の内容で作成する。

```css
#tabbrowser-tabs {
    visibility: collapse !important;
}

#sidebar-header {
    visibility: collapse !important;
}
```

Firefoxを再起動して反映しているか確認。

## 参考

- [FirefoxCSS-Store.github.io/README.md at main · FirefoxCSS-Store/FirefoxCSS-Store.github.io · GitHub](https://github.com/FirefoxCSS-Store/FirefoxCSS-Store.github.io/blob/main/README.md#generic-installation)
- [MacでFireFoxのタブを左側に配置し、上部のタブの領域を削除（非表示）する方法 - Qiita](https://qiita.com/chatrate/items/50d9338453f7d2a19ace)
