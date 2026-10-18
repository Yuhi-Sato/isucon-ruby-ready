# stackprofでアプリのCPUをサンプリングする起動フック。
# アプリのコードは変更せず、systemdのdrop-in（scripts/stackprof-on.sh が作る）が RUBYOPT=-r<このファイル> で読み込む。
# プロセス終了時（at_exit）に STACKPROF_OUT_DIR へ <日時>-<pid>.dump を書き出す。
# bundler起動前に読まれるため、stackprofはGemfileではなくシステム側のgem（scripts/install-stackprof.sh）から読む。

require "fileutils"
require "stackprof"

OUT_DIR = ENV.fetch("STACKPROF_OUT_DIR")
FileUtils.mkdir_p(OUT_DIR)

def stackprof_start
  StackProf.start(mode: :cpu, interval: 1000, aggregate: true)
end

stackprof_start

# pumaのクラスタモード等でforkされた子プロセスは、親のタイマーを引き継がないので開始し直す
if Process.respond_to?(:_fork)
  Process.singleton_class.prepend(Module.new do
    def _fork
      pid = super
      if pid.zero?
        begin
          StackProf.stop
        rescue StandardError
          nil
        end
        stackprof_start
      end
      pid
    end
  end)
end

at_exit do
  StackProf.stop
  # forkして即終了するだけのプロセスなどサンプルが無いものはdumpを残さない
  results = StackProf.results
  next if results.nil? || results[:samples].to_i.zero?

  path = File.join(OUT_DIR, "#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{Process.pid}.dump")
  File.binwrite(path, Marshal.dump(results))
end
