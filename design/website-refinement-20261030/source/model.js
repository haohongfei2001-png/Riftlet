/* Synthetic demonstration model. No real files, transport, or platform claims.
 * The transition reducer intentionally separates request, positive start,
 * completion, failure, and an unconfirmed result. Timers live in the view only.
 */
(function(root, factory) {
  const Model = factory();
  if (typeof module === 'object' && module.exports) module.exports = Model;
  else root.RiftletModel = Model;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';
  const kinds = [
    {symbol:'hero-page-art',view:'0 0 288 150',w:58,h:58*150/288,lw:228,lh:228*150/288},
    {symbol:'capture-b',view:'0 0 240 170',w:58,h:58*170/240,lw:166,lh:166*170/240},
    {symbol:'capture-c',view:'0 0 110 160',w:38,h:38*160/110,lw:80,lh:80*160/110}
  ];
  return class DemoModel {
    constructor(onChange = () => {}) {
      this.onChange = onChange; this.epoch = 0; this.events = [];
      this.reset(3);
    }
    emit(type, item = null) {
      this.events.push({type, id:item?.id ?? null, attempt:item?.attempt ?? null, epoch:this.epoch});
      if (this.events.length > 100) this.events.shift();
      this.onChange(type, item);
    }
    reset(count = 3) {
      this.epoch++; this.items=[]; this.nextId=1;
      for(let i=0;i<Math.min(3,Math.max(0,count));i++) this.add(false);
      this.emit('reset');
    }
    add(notify = true) {
      if(this.items.filter(x=>x.visible).length >= 3) return null;
      const id=this.nextId++;
      const item={id,...kinds[(id-1)%3],state:'available',visible:true,attempt:0,inputs:0,card:false,cardRemoved:false,dismissed:false};
      this.items.push(item); if(notify) this.emit('add',item); return item;
    }
    request(id, scenario='success') {
      const item=this.items.find(x=>x.id===Number(id));
      if(!item || !item.visible || !['available','failed','blocked'].includes(item.state)) return null;
      if(!['success','failure','unknown','no-start'].includes(scenario)) throw new TypeError('Unknown synthetic scenario');
      item.attempt++;item.inputs++;item.state='pending';item.card=false;item.cardRemoved=false;
      const ticket={id:item.id,attempt:item.attempt,epoch:this.epoch,target:'synthetic-draft-only',scenario};
      this.emit('request',item);return ticket;
    }
    signal(ticket, event) {
      if(!ticket || ticket.epoch!==this.epoch || ticket.target!=='synthetic-draft-only') return false;
      const item=this.items.find(x=>x.id===ticket.id);
      if(!item || item.attempt!==ticket.attempt) return false;
      if(event==='no-start' && item.state==='pending') {
        item.state='blocked';item.visible=true;item.card=false;
      } else if(event==='positive-start' && item.state==='pending') {
        item.state='started';item.visible=false;item.card=true;
      } else if(item.state==='started' && ['ready','failure','unknown'].includes(event)) {
        if(event==='failure') {
          item.state='failed';item.card=false;
          item.visible=!item.dismissed && !item.cardRemoved;
        } else {item.state=event;item.visible=false;}
      } else return false;
      this.emit(event,item);return true;
    }
    removeCard(id) {
      const item=this.items.find(x=>x.id===Number(id));
      if(!item || !item.card) return false;
      item.card=false;item.cardRemoved=true;this.emit('remove-card',item);return true;
    }
    snapshot() {
      return {epoch:this.epoch,items:this.items.map(x=>({...x})),events:this.events.map(x=>({...x}))};
    }
  };
});
