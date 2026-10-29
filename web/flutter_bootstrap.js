{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('tempo-sw.js').catch(error => {
      console.warn('Offline installation unavailable:', error);
    });
  });
}
