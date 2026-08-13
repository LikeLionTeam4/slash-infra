#!/bin/bash
# cloud-init user_data — 최초 부팅 시 1회만 실행된다. stop/start로는 재실행되지
# 않으므로, EBS에 남은 Ollama 설치·모델을 그대로 두고 재기동만 하면 된다(docs §5-1).
set -euo pipefail

# cloud-init이 이 스크립트를 실행하는 셸엔 $HOME이 비어 있다 — ollama CLI가 모델
# 저장 경로를 정하려고 $HOME을 참조하는데(`ollama pull` 시 "panic: $HOME is not
# defined"), systemd로 도는 ollama 서비스 자체는 자체 유닛의 User=ollama 환경이라
# 영향 없다. root로 pull하는 이 스크립트에서만 명시해주면 된다.
export HOME=/root

curl -fsSL https://ollama.com/install.sh | sh

# 기본값은 127.0.0.1:11434(로컬만 허용)이라 EKS 파드에서 접근이 안 된다 —
# ollama SG가 EKS SG에서만 11434 인바운드를 허용하므로 0.0.0.0으로 바인딩해도
# 외부(인터넷)에는 노출되지 않는다.
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

until curl -sf http://127.0.0.1:11434/api/tags >/dev/null; do
  sleep 2
done

ollama pull ${ollama_model}
