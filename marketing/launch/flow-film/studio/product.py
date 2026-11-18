"""Riftlet 1.0.5 right-edge presentation plates for the Flow film.

The two supported film modes are 'tray' and 'slit'. Input is a list of PIL
source pictures. Arrivals are (time, picture_index). Each click is
(press_time, attachment_start_time, pointer_clear_refill_time, picture_index).
Times are in seconds. frame() returns a read-only 320x300 RGBA plate at the
requested scale. target() returns the corresponding local pointer coordinate.
"""
from functools import lru_cache
from math import floor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = (320, 300)
SAMPLE = 3
RIGHT = 284
BOTTOM = 255
SLIT_ZOOM = 1.33
SWALLOW = 0.120
SHIFT = 0.160
REVEAL = 0.170
LANCZOS = Image.Resampling.LANCZOS


def clamp(x):
    return max(0., min(1., x))


def smooth(x):
    u = clamp(x)
    return u*u*(3-2*u)


def units(value):
    return round(value*SAMPLE)


def rect_coords(rect):
    return tuple(units(v) for v in rect)


def blank():
    return Image.new('RGBA', (units(SIZE[0]), units(SIZE[1])))


def tint(alpha, color):
    layer = Image.new('RGBA', alpha.size, color)
    layer.putalpha(alpha)
    return layer


@lru_cache(maxsize=20)
def glass(height_px):
    height = height_px/SAMPLE
    if height < 1:
        return blank()
    bounds = rect_coords((RIGHT-246, BOTTOM-height, RIGHT, BOTTOM))
    mask = Image.new('L', blank().size)
    ImageDraw.Draw(mask).rounded_rectangle(bounds, radius=units(24), fill=255)
    shadow = Image.new('L', mask.size)
    shadow.paste(mask, (0, units(6)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(units(7)))
    # Diffuse shadow only on the outside of the translucent material.
    shadow.paste(0, mask=mask)
    stage = tint(shadow.point(lambda a: round(a*.23)), (19,25,45))
    stage.alpha_composite(tint(mask.point(lambda a: round(a*.64)), (234,235,250)))
    edge = blank()
    d = ImageDraw.Draw(edge)
    d.rounded_rectangle(bounds, radius=units(24), outline=(255,255,255,184), width=units(1))
    # The lower contact rim is restrained as on the light violet glass preset.
    stage.alpha_composite(edge)
    return stage


@lru_cache
def ordinal_font():
    for path in ('/System/Library/Fonts/SFNSMono.ttf',
                 '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'):
        if Path(path).exists():
            return ImageFont.truetype(path, units(11*SLIT_ZOOM))
    return ImageFont.load_default(size=units(11*SLIT_ZOOM))


class Product:
    def __init__(self, cards):
        self.cards = tuple(card.convert('RGB') for card in cards)

    def _slot(self, mode, count, slot, index):
        if mode == 'tray':
            return RIGHT-246 + 7 + (slot%2)*118.5 + 56.75, BOTTOM - (155 if count >= 2 and slot<2 else 58)
        if mode != 'slit':
            raise ValueError("mode must be 'tray' or 'slit'")
        card = self.cards[index]
        ratio = min(72/card.width, 56/card.height)*SLIT_ZOOM
        exposed = card.width*ratio*.75
        return RIGHT-exposed/2, 43+slot*60*SLIT_ZOOM

    def _state(self, mode, t, arrivals, clicks):
        events = [(at, True, index) for at, index in arrivals if at <= t]
        events.extend((refill, False, index) for _, _, refill, index in clicks if refill <= t)
        active, old = [], []
        last = float('-inf')
        for at, arriving, index in sorted(events):
            old = active.copy()
            if arriving:
                active.append(index)
            else:
                active.remove(index)
            last = at
        positions = {}
        shift = smooth((t-last)/SHIFT)
        for slot, index in enumerate(active[:4]):
            x, y = self._slot(mode, len(active), slot, index)
            if index in old[:4]:
                prev_x, prev_y = self._slot(mode, len(old), old.index(index), index)
                x, y = prev_x + (x-prev_x)*shift, prev_y + (y-prev_y)*shift
            positions[index] = (x, y)
        return active[:4], old[:4], positions, shift

    def target(self, mode, t, arrivals, clicks=(), index=0, scale=1.0):
        """Return a pointer hot spot in the plate; query before attachment START."""
        _, _, positions, _ = self._state(mode,t,arrivals,clicks)
        x, y = positions[index]
        return x*scale, y*scale

    @lru_cache(maxsize=20)
    def _tile(self, mode, index):
        source = self.cards[index]
        if mode == 'tray':
            ratio = min(108/source.width, 73.75/source.height)
            size = (units(source.width*ratio), units(source.height*ratio))
            picture = source.resize((max(1,size[0]), max(1,size[1])), LANCZOS)
            rim, foot = units(2.75), units(.75)
            w, h = picture.width+2*rim, picture.height+2*rim+foot
            tile = Image.new('RGBA',(w,h))
            d = ImageDraw.Draw(tile)
            d.rounded_rectangle((0,0,w-1,h-1), radius=round(w*9/114),fill=(234,232,253),
                                outline=(255,255,255),width=2)
            tile.paste(picture,(rim,rim))
            return tile
        ratio = min(72/source.width,56/source.height)*SLIT_ZOOM
        size = max(1,units(source.width*ratio)), max(1,units(source.height*ratio))
        picture = source.resize(size,LANCZOS)
        width = max(1,round(picture.width*.75))
        tile = picture.crop((0,0,width,picture.height)).convert('RGBA')
        mask = Image.new('L',tile.size)
        d = ImageDraw.Draw(mask)
        radius=units(2.6*SLIT_ZOOM)
        d.rounded_rectangle((0,0,tile.width+radius,tile.height-1), radius=radius, fill=255)
        tile.putalpha(mask)
        d = ImageDraw.Draw(tile)
        d.rounded_rectangle((0,0,tile.width+radius,tile.height-1), radius=radius,
                            outline=(42,57,61,138),width=2)
        gradient = Image.new('RGBA', tile.size)
        right = ImageDraw.Draw(gradient)
        for offset in range(units(2*SLIT_ZOOM)):
            a=round(34*(1-offset/units(2*SLIT_ZOOM))**2)
            right.line((width-1-offset,0,width-1-offset,tile.height-1), fill=(0,8,14,a))
        tile.alpha_composite(gradient)
        return tile

    @lru_cache(maxsize=96)
    def _number(self,n):
        f=ordinal_font()
        width = max(units(10),round(f.getlength(str(n))+units(2*SLIT_ZOOM)))
        height = units(14*SLIT_ZOOM)
        plate = Image.new('RGBA',(width,height))
        d=ImageDraw.Draw(plate)
        d.rounded_rectangle((0,0,width-1,height-1), radius=units(2*SLIT_ZOOM), fill=(248,250,249,240))
        d.text((width/2,height/2),str(n),font=f,anchor='mm',fill=(70,84,93))
        return plate

    def frame(self, mode, t, arrivals, clicks=(), scale=1.0):
        active, old, positions, shift = self._state(mode,t,arrivals,clicks)
        def height(ids):
            return 212 if len(ids)>=2 else 115 if ids else 0
        # The first surface takes its settled size at first capture. The existing
        # tray lifts its first row when the second illustration arrives.
        h = height(active)
        if old and active:
            h = height(old)+(h-height(old))*shift
        arrival_dates=dict((index,at) for at,index in arrivals)
        click_dates={index:(down,start,refill) for down,start,refill,index in clicks}
        signature=[]
        for slot, index in enumerate(active):
            x,y=positions[index]
            show=1-(1-clamp((t-arrival_dates[index])/REVEAL))**3
            down,start,_=click_dates.get(index,(float('inf'),)*3)
            exit_amount=clamp((t-start)/SWALLOW)
            pressure=0.
            if down<=t<start:
                pressure=1-smooth((t-down)/.090)
            signature.append((index,slot+1,units(x),units(y),round(show*1000),
                              round(exit_amount*1000),round(pressure*1000)))
        return self._render(mode,units(h),tuple(signature),round(scale,4))

    @lru_cache(maxsize=8)
    def _render(self,mode,height_px,signature,scale):
        if scale <= 0:
            raise ValueError('scale must be positive')
        visible = [item for item in signature if item[5]<1000]
        result = glass(height_px).copy() if mode=='tray' and visible else blank()
        if mode=='slit' and visible:
            top = min(y-self._tile(mode,idx).height/2 for idx,_,_,y,*_ in visible)
            bottom = max(y+self._tile(mode,idx).height/2 for idx,_,_,y,*_ in visible)
            ImageDraw.Draw(result).line((units(RIGHT),round(top),units(RIGHT),round(bottom)),
                                        fill=(24,40,33,160),width=max(1,units(.5*SLIT_ZOOM)))
        for index,ordinal,x,y,show,exit_milli,press_milli in visible:
            tile = self._tile(mode,index)
            left,top=x-tile.width//2,y-tile.height//2
            exit_amount=exit_milli/1000
            dx=round(tile.width*(1-show/1000)+(tile.width+units(4))*exit_amount**1.35+
                     units(1.5)*press_milli/1000)
            if dx<tile.width:
                shown=tile.crop((0,0,tile.width-dx,tile.height)) if dx else tile
                if exit_milli:
                    shown=shown.copy()
                    shown.putalpha(shown.getchannel('A').point(lambda a: round(a*(1-exit_amount))))
                if mode=='tray' and not exit_milli:
                    # Soft contact shadow follows the individual original-image backing.
                    sh = tint(shown.getchannel('A').filter(ImageFilter.GaussianBlur(units(1.3)))
                              .point(lambda a:round(a*.18)),(31,33,54))
                    result.alpha_composite(sh,(left+dx,top+units(1.5)))
                result.alpha_composite(shown,(left+dx,top))
            if mode=='slit':
                number=self._number(ordinal)
                if exit_milli:
                    number=number.copy()
                    number.putalpha(number.getchannel('A').point(lambda a:round(a*(1-exit_amount))))
                result.alpha_composite(number,(left-units(8*SLIT_ZOOM)-number.width,y-number.height//2))
        out=(max(1,round(SIZE[0]*scale)),max(1,round(SIZE[1]*scale)))
        return result if result.size==out else result.resize(out,LANCZOS)
