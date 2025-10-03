;; ChatGPT AI integration.
(use-package chatgpt-shell
  :ensure t
  :config
  (setq chatgpt-shell-save-session t)
  (global-set-key (kbd "C-c g") #'chatgpt-shell)
  (setq chatgpt-shell-openai-key my-openai-api-key)
  (setq chatgpt-shell-anthropic-key my-anthropic-api-key)
  (setq chatgpt-shell-google-key my-gemini-api-key))

(use-package ollama-buddy
  :ensure t
  :commands (ollama-buddy-chat ollama-buddy-prompt-region ollama-buddy-prompt-buffer)
  :config)
