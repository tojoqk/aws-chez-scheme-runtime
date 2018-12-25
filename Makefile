layer:
	docker run --rm `docker build -q .` | tar x layer

.PHONY: clean

clean:
	-rm -rf layer
