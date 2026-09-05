#!/bin/bash
set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $1"; }
die() { log "ERROR: $1"; exit "${2:-1}"; }

# Единое место для каталога ролей
ROLES_DIR="/workspace/roles"

# ============================================================
# Функция установки Ansible-ролей
# ============================================================
install_roles() {
    log "Installing Ansible roles into $ROLES_DIR..."
    mkdir -p "$ROLES_DIR"

    local req_file=""
    if [ -f /workspace/requirements.yml ]; then
        req_file="/workspace/requirements.yml"
    elif [ -f /workspace/playbooks/requirements.yml ]; then
        req_file="/workspace/playbooks/requirements.yml"
    elif [ -f /workspace/roles/requirements.yml ]; then
        req_file="/workspace/roles/requirements.yml"
    fi

    if [ -n "$req_file" ]; then
        log "Found requirements file: $req_file"
        ansible-galaxy role install -r "$req_file" --force -p "$ROLES_DIR" --ignore-errors || {
            log "WARNING: Some roles failed to install. Check the output above."
        }
    else
        log "requirements.yml not found. Skipping role installation."
    fi
    log "Roles installation completed."
}

# ============================================================
# Определение режима разработчика по наличию ANSIBLE_PLAYBOOK_SRC
# ============================================================
DEV_MODE=false
if [ -n "${ANSIBLE_PLAYBOOK_SRC:-}" ]; then
    DEV_MODE=true
    log "Development mode detected (ANSIBLE_PLAYBOOK_SRC is set)."
else
    log "Production mode (ANSIBLE_PLAYBOOK_SRC is not set)."
fi

# ============================================================
# Настройка Git safe.directory (для всех режимов)
# ============================================================
git config --global --add safe.directory /workspace 2>/dev/null || true

# ============================================================
# Режим разработки
# ============================================================
if [ "$DEV_MODE" = true ]; then
    log "Using mounted code from ${ANSIBLE_PLAYBOOK_SRC}"
    if [ -z "$(ls -A .)" ]; then
        log "WARNING: Working directory is empty. Did you mount your code?"
    fi
    install_roles
    
    if [ $# -gt 0 ]; then
        log "Executing: $*"
        exec "$@"
    else
        log "No command provided, staying idle"
        tail -f /dev/null
    fi
    exit 0
fi

# ============================================================
# Продакшн-режим: проверка Git и клонирование (публичный репозиторий)
# ============================================================
GIT_REPO="${GIT_REPO:?GIT_REPO is required. Check ANSIBLE_GIT_REPO in .env}"
GIT_BRANCH="${GIT_BRANCH:-main}"

command -v git &>/dev/null || die "git is not installed"
log "Working directory: $PWD"

# Формируем URL для клонирования (без токена)
if [[ "$GIT_REPO" =~ ^https?:// ]]; then
    CLONE_URL="$GIT_REPO"
else
    CLONE_URL="https://github.com/${GIT_REPO}.git"
fi

# ============================================================
# Клонирование или обновление
# ============================================================
if [ -d .git ]; then
    log "Existing repository found. Updating..."
    git remote set-url origin "$CLONE_URL" 2>/dev/null || true
    git fetch origin || die "Failed to fetch from origin"
    
    if git show-ref --verify --quiet "refs/heads/$GIT_BRANCH"; then
        git checkout "$GIT_BRANCH" || die "Failed to checkout $GIT_BRANCH"
        git pull origin "$GIT_BRANCH" 2>/dev/null || log "Pull failed, continuing with local state"
    else
        git checkout -b "$GIT_BRANCH" "origin/$GIT_BRANCH" || die "Failed to create branch $GIT_BRANCH"
    fi
else
    log "Cloning $GIT_REPO (branch: $GIT_BRANCH)..."
    git clone --branch "$GIT_BRANCH" "$CLONE_URL" . || die "Clone failed. Check GIT_REPO and GIT_BRANCH"
fi

log "Repository ready"
log "Branch: $(git branch --show-current)"

# ============================================================
# Установка ролей после клонирования
# ============================================================
install_roles

# ============================================================
# Запуск команды или ожидание
# ============================================================
if [ $# -gt 0 ]; then
    log "Executing: $*"
    exec "$@"
else
    log "No command provided, staying idle"
    tail -f /dev/null
fi