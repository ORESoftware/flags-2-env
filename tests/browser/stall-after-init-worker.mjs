self.addEventListener("message", (event) => {
  const request = event.data;
  if (request?.method === "__init") {
    self.postMessage({ id: request.id, ok: true, value: true });
  }
});
