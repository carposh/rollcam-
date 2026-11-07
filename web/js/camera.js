// getUserMedia camera. Captures the full video frame; the 3:2 crop happens at develop time.
export class Camera {
  constructor(video) {
    this.video = video;
    this.facing = 'environment';
    this.stream = null;
    this.track = null;
    this.torchSupported = false;
    this.error = null;
    this.starting = null;
  }

  get ready() {
    return !!this.stream && this.video.readyState >= 2 && this.video.videoWidth > 0;
  }

  async start() {
    if (this.stream) return;
    if (this.starting) return this.starting;
    this.starting = (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) throw Object.assign(new Error('No camera API'), { name: 'NotSupportedError' });
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: false,
          video: { facingMode: { ideal: this.facing }, width: { ideal: 3840 }, height: { ideal: 2160 } },
        });
        this.stream = stream;
        this.track = stream.getVideoTracks()[0];
        const caps = this.track.getCapabilities ? this.track.getCapabilities() : {};
        this.torchSupported = !!caps.torch;
        this.video.srcObject = stream;
        this.video.classList.toggle('mirrored', this.facing === 'user');
        await this.video.play().catch(() => {});
        this.error = null;
      } catch (e) {
        this.error = e.name || 'Error';
        throw e;
      } finally {
        this.starting = null;
      }
    })();
    return this.starting;
  }

  stop() {
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.track = null;
    this.video.srcObject = null;
  }

  async flip() {
    this.facing = this.facing === 'environment' ? 'user' : 'environment';
    this.stop();
    await this.start();
  }

  async setTorch(on) {
    if (!this.torchSupported || !this.track) return;
    try {
      await this.track.applyConstraints({ advanced: [{ torch: on }] });
    } catch {
      // Best effort: no torch still takes the picture.
    }
  }

  /** Returns a JPEG Blob of the current frame. */
  async capture({ torch = false } = {}) {
    if (!this.ready) throw new Error('Camera not ready');
    if (torch) {
      await this.setTorch(true);
      await new Promise((r) => setTimeout(r, 450)); // let exposure settle on the lit scene
    }
    try {
      const w = this.video.videoWidth, h = this.video.videoHeight;
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      canvas.getContext('2d').drawImage(this.video, 0, 0, w, h);
      const blob = await new Promise((res) => canvas.toBlob(res, 'image/jpeg', 0.93));
      canvas.width = canvas.height = 0;
      if (!blob) throw new Error('Encode failed');
      return blob;
    } finally {
      if (torch) this.setTorch(false);
    }
  }
}
