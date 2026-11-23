'use strict';
// CDP messages stay on two inherited pipes in this test's own disposable child.
// No debug port, browser enumeration, or connection to an existing process.
class FixtureDriver {
  constructor(child) {
    this.output = child.stdio[3];
    this.pending = new Map();
    this.nextRequest = 1;
    let tail = '';
    child.stdio[4].setEncoding('utf8');
    child.stdio[4].on('data', chunk => {
      const frames = (tail + chunk).split('\0');
      tail = frames.pop();
      for (const frame of frames) {
        if (!frame) continue;
        const message = JSON.parse(frame), pending = this.pending.get(message.id);
        if (!pending) continue;
        this.pending.delete(message.id);
        clearTimeout(pending.timer);
        if (message.error) pending.reject(Error(message.error.message));
        else pending.resolve(message.result);
      }
    });
    const closed = () => {
      for (const req of this.pending.values()) { clearTimeout(req.timer); req.reject(Error('fixture pipe closed')); }
      this.pending.clear();
    };
    child.stdio[4].once('close', closed);
    this.output.on('error', closed);
  }
  call(method, params = {}, sessionId) {
    const id = this.nextRequest++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(Error(method + ' timed out')); }, 8000);
      this.pending.set(id, {resolve,reject,timer});
      this.output.write(JSON.stringify({id,method,params,sessionId}) + '\0');
    });
  }
  async open(url) {
    const {targetId} = await this.call('Target.createTarget', {url,background:false});
    const {sessionId} = await this.call('Target.attachToTarget', {targetId,flatten:true});
    return {targetId,sessionId};
  }
  async fixture(tab, method, ...args) {
    const expression = 'window.qa[' + JSON.stringify(method) + '](...' + JSON.stringify(args) + ')';
    const res = await this.call('Runtime.evaluate', {expression,returnByValue:true,awaitPromise:true}, tab.sessionId);
    if (res.exceptionDetails) throw Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
    return res.result.value;
  }
}
module.exports = {FixtureDriver};
