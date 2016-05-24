FROM scratch
ADD build/triple-dub-dot-rb-lab-build/triple-dub-dot-rb-lab /triple-dub-dot-rb-lab
ADD config.ru /config.ru
EXPOSE 9292
CMD ["/triple-dub-dot-rb-lab", "9292"]
