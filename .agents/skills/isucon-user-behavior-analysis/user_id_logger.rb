# ユーザー行動履歴ロガー（isucon-user-behavior-analysis スキル参照）。
# セッションのユーザーIDをX-User-Idレスポンスヘッダーに載せる。
# nginxがこれをLTSVのuseridフィールドに記録し、ベンチマーカーへは
# proxy_hide_headerで隠す（tool-config/nginx/ltsv-log-format.conf 参照）。
#
# 使い方: webapp/ruby/ にコピーし、config.ru に以下を追加する。
#   require_relative "user_id_logger"
#   use UserIdLogger
#
# レスポンス経路（@app.call の後）でセッションを読むため、セッション
# ミドルウェアがconfig.ruにあってもSinatra内（enable :sessions）にあっても、
# 挿入位置はどちらでも動く。
class UserIdLogger
  # 問題のアプリがsessionに入れているユーザーIDのキー名に合わせて書き換える
  SESSION_KEY = "user_id"

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    session = env["rack.session"]
    user_id = session && (session[SESSION_KEY] || session[SESSION_KEY.to_sym])
    # Rack 3はヘッダー名の小文字を要求する（Rack 2でも問題なく動く）
    headers["x-user-id"] = user_id.to_s if user_id
    [status, headers, body]
  end
end
