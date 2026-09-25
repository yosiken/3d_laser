# Curl Noise Lock-on Laser (Godot 4.3)

カールノイズで軌道を曲げる、3D空間のロックオンレーザーのデモです。
Godot 4.3 の Compatibility レンダラ（WebGL2）で動くので、そのままブラウザで動かせます。

![screenshot](docs/screenshot.png)

## 操作

| 入力 | 動作 |
| --- | --- |
| 左クリック長押し / タッチ長押し / Space 長押し | 照準をなぞって敵をロックオン（1体につき最大4回、合計24回まで） |
| 離す | ロックした数だけホーミングレーザーを発射 |
| `A` | 自動デモの ON/OFF（3秒操作がないと、自動でロックして発射します） |
| `C` | カールノイズの ON/OFF（違いを見比べる用） |

## ブラウザで確認する

### A. GitHub Pages（おすすめ）
1. リポジトリの **Settings → Pages → Build and deployment → Source** を **GitHub Actions** にします。
2. push すると `.github/workflows/deploy-web.yml` が Web 向けに書き出して Pages にデプロイします
   （Actions タブから手動実行も可）。
3. `https://<ユーザー名>.github.io/3d_laser/` を開きます。

シングルスレッド版（`variant/thread_support=false`）で書き出すので、
COOP/COEP ヘッダーのない GitHub Pages でもそのまま動きます。

### B. ローカル
```sh
godot --headless --export-release "Web" build/web/index.html   # 4.3 の Web 用エクスポートテンプレートが必要
python3 -m http.server 8000 -d build/web                        # http://localhost:8000 を開く
```
Godot エディタで開いた場合は、右上の「Remote Debug → Run in Browser」でも確認できます。

## 仕組み

- `scripts/curl_noise.gd` — 3つの Simplex ノイズをベクトルポテンシャル ψ とし、
  中心差分で `curl ψ` を計算します。発散ゼロの流れ場なので、湧き出しや吸い込みがなく、
  滑らかに渦を巻く軌道になります。時間でサンプル位置をずらして流れ場を変化させています。
- `scripts/laser_system.gd` — 各レーザーは
  `位置 = lerp(発射位置, 目標, u^1.7) + オフセット × エンベロープ(u)` で動きます。
  オフセットは発射時に外向きの初速を与えた粒子で、カールノイズの力を受けながら減衰します。
  飛行時間の終盤でエンベロープを 0 にするので、どれだけ曲がっても必ず命中します。
  軌跡はカメラに向いたリボン（太い発光層＋細い芯）と先端のフレアを
  1つの `ArrayMesh` に毎フレームまとめて描画しています（加算合成）。
- `scripts/enemy.gd` — 敵も同じカールノイズの流れに乗って漂います。
- `scripts/main.gd` — シーン構築、ロックオン判定（画面上の照準円との距離）、
  発射キュー、爆発エフェクト、自動デモ。
- `scripts/hud.gd` — 照準・ロックオンマーカー・スコアの 2D 描画。

主なパラメータ（`laser_system.gd` 冒頭）:
`CURL_STRENGTH`（曲がり具合）、`DAMPING`（減衰）、`TRAIL_LEN`（軌跡の長さ）、
`GLOW_WIDTH` / `CORE_WIDTH`（太さ）。流れ場の細かさは `main.gd` の `CurlNoise.new(seed, frequency)` です。
