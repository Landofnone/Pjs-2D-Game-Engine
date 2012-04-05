/**
 * Boundaries are unidirectionally passable,
 * and are positionable in the same way that
 * anything else is.
 */
class Boundary extends Positionable {
  private float PI2 = 2*PI;

  // extended adminstrative values
  float dx, dy;
  float xw, yh;
  float minx, maxx, miny, maxy;
  float angle, cosa, sina, cosma, sinma;

  // boundaries can be linked
  Boundary prev, next;
  
  float boundingThreshold = 1.5;
  
  boolean disabled = false;

  // attached actors
  ArrayList<Positionable> attached;

  /**
   * When we build a boundary, we record a
   * vast number of shortcut values so we
   * don't need to recompute them constantly.
   */
  Boundary(float x1, float y1, float x2, float y2) {
    // coordinates
    x = x1;
    y = y1;
    xw = x2;
    yh = y2; 
    // deltas
    dx = x2-x1;
    dy = y2-y1;
    updateBounds();
    updateAngle();
    attached = new ArrayList<Positionable>();
  }
  
  /**
   * Update our bounding box information
   */
  void updateBounds() {
    xw = x + dx;
    yh = y + dy;
    minx = min(x, xw);
    maxx = max(x, xw);
    miny = min(y, yh);
    maxy = max(y, yh);
  }
  
  /**
   * Update our angle in the world
   */
  void updateAngle() {
    angle = atan2(dy, dx);
    if (angle < 0) angle += 2*PI;
    cosma = cos(-angle);
    sinma = sin(-angle);
    cosa = cos(angle);
    sina = sin(angle);
  }

  /**
   * When we reposition a boundary,
   * anything that is attached to it
   * must be repositioned, too.
   */
  void setPosition(float _x, float _y) {
    // move all actors attached to this boundary
    for(Positionable a: attached) {
      a.moveBy(x-_x,y-_y);
    }
    // and of course move the boundary itself.
    super.setPosition(_x,_y);
    updateBounds();
  }
  
  void moveBy(float dx, float dy) {
    super.moveBy(dx,dy);
    updateBounds();
  }

  /**
   * attach an actor to this boundary. Attached
   * actors do not test for additional boundary
   * collisions, and get their impulse from the
   * boundary, rather than directly.
   */
  void attach(Positionable a) {
    attached.add(a);
  }

  /**
   * detach an actor from this boundary
   */
  void detach(Positionable a) {
    attached.remove(a);
  }

  /**
   * detach all actors from this boundary
   */
  void detachAll() {
    for(Positionable a: attached) {
      a.detach(this);
    }
    attached = new ArrayList<Positionable>();
  }

  /**
   * This boundary is part of a chain, and
   * the previous boundary is:
   */
  void setPrevious(Boundary b) { prev = b; }

  /**
   * This boundary is part of a chain, and
   * the next boundary is:
   */
  void setNext(Boundary b) { next = b; }

  /**
   * Enable this boundary
   */
  void enable() { disabled = false; }

  /**
   * Disable this boundary
   */
  void disable() { disabled = true; }

  /**
   * Point outside the bounding box for this boundary?
   */
  boolean outOfBounds(float x, float y) {
    if(disabled) return true;
    return (x<minx-boundingThreshold || x>maxx+boundingThreshold || y<miny-boundingThreshold || y>maxy+boundingThreshold);
  }

  /**
   * Is this boundary blocking the specified actor?
   */
  float[] blocks(Actor a) {
    if(disabled) return null;

    // get the basic positioning information
    float px = a.getPrevX(),
          py = a.getPrevY(),
          cx = a.getX(),
          cy = a.getY(),
          dx = cx-px,
          dy = cy-py;

    // no trajectory means nothing has changed
    // since the last time we checked blocking.
    if(dx==0 && dy==0) { return null; }

    // continue: get the current and previous bounding boxes
    float[] prev = a.getBoundingBox();
    prev[0] -= dx;  prev[1] -= dy;
    prev[2] -= dx;  prev[3] -= dy;
    prev[4] -= dx;  prev[5] -= dy;
    prev[6] -= dx;  prev[7] -= dy;
    float[] current = a.getBoundingBox();

    // check if any of the corners is blocked. If so, signal a block.
    float[] alignment = { a.width/2, a.height,
                         -a.width/2, a.height,
                         -a.width/2, 0,
                          a.width/2, 0};

    // check if any of the corners is blocked
    for(int i=0; i<8; i+=2) {
      float[] overlap = blocks(prev[i], prev[i+1], current[i], current[i+1]);
      if(overlap!=null) {
        // FIXME: add in a 'but not actually blocked if: ...' criterium
        //        so that we don't get "glued" to boundaries that we're
        //        just passing through.
        if(!above(prev)) { continue; }

        // correct the intersection point for the corner's
        // offset with respect to the sprite's anchor:
        overlap[0] += alignment[i];
        overlap[1] += alignment[i+1];
        return overlap; }}

    return null;
  }
  
  /**
   * Is the bounding box entirely above this boundary?
   */
  boolean above(float[] bounds) {
    boolean failed = false;
    for(int i=0; i<8; i+=2) {
      if(!onPassThroughSide(x, y, bounds[i], bounds[i+1])) {
        // we allow one of the four corners to be below
        // the boundary. This means slants don't break.
        if(!failed) { failed = true; }
        else { return false; }}}
    return true;
  }

  /**
   * May something on a path from (x1,y1) to (x2,y2) pass through this platform?
   */
  protected float[] blocks(float x1, float y1, float x2, float y2) {
    // perform a translation-rotation about (x3,y3)
    float[] tr = translateRotateXY3(x1, y1, x2, y2, x, y, xw, yh);

    // Is our line segment in range? Because our
    // reference line is now flat, we can simply
    // check the x-coordinates.
    if(tr[0] < 0     && tr[2] < 0)     { return null; } // x1<0 and x2<0
    if(tr[0] > tr[6] && tr[2] > tr[6]) { return null; } // x1>x3 and x2>x3
    
    // let's rule out colinear paths, too.
    // Those will never block.
    if(tr[1]==0 && tr[3]==0) { return null; }
    

    // Let's find out where these two lines meet.
    float dx = tr[2] - tr[0];       // x2n - x1n;
    float dy = tr[3] - tr[1];       // y2n - y1n;
    float factor = -tr[1] / dy;     // -y1n / dy
    float ix = tr[0] + factor * dx; // x1n + factor*dx

    // is this a real intersection (i.e. lying on both line
    // segments) or virtual intersection?
    if(factor<=0 || factor>=1) { return null; }

    // At this point we know the boundary and path intersect,
    // but we only want this to happen if the actor's on the
    // 'wrong' side of the unidirectionally passable boundary.
    if (onPassThroughSide(x1, y1, x2, y2)) return null;

    // Okay, this actor cannot pass. compute the halting point.
    return new float[]{x + ix*cos(angle), y + ix*sin(angle)};
  }

  /**
   * Perform a coordinate tranlation/rotation so that
   * the boundary starts at 0,0 and runs to [...],0
   * with the trajectory (x1,y1)-(x2,y2) transformed
   * accordingly.
   *
   * returns float[9], with four coordinate pairs and
   *                   the angle used for the rotation.
   */
  float[] translateRotateXY3(float x1, float y1, float x2, float y2, float x3, float y3, float x4, float y4)
  {
    // Translate so that x3/y3 lie on 0/0
    x1 -= x3;    y1 -= y3;
    x2 -= x3;    y2 -= y3;
    x4 -= x3;    y4 -= y3;

    // rotate x1/y1
    float x1n = x1 * cosma - y1 * sinma,
          y1n = x1 * sinma + y1 * cosma;

    // rotate x2/y2
    float x2n = x2 * cosma - y2 * sinma,
          y2n = x2 * sinma + y2 * cosma;

    // rotate x4/y4
    float x4n = x4 * cosma - y4 * sinma,
          y4n = 0; // by definition

    return new float[]{x1n, y1n, x2n, y2n, 0, 0, x4n, 0, angle};
  }

  /**
   * Determine which side and incoming path
   * is actually incoming from.
   */
  // FIXME: this can be done more efficiently, rather than readably.
  // FIXME: this seems to still cause pass-through problems when x1/y1
  //        is located on the boundary line.
  boolean onPassThroughSide(float x1, float y1, float x2, float y2) {
    float local = atan2(dy, dx);
    local = (local<0? PI2 + local : local);
    float path = atan2(y2-y1, x2-x1);
    path = (path<0? PI2+path : path);
    float diff = (PI2 + path - local)%PI2;
    return (diff>PI);
  }

  /**
   * redirect a force along this boundary's surface.
   */
  float[] redirectForce(float fx, float fy) {
    float[] tr = translateRotateXY3(x,y,x+fx,y+fy, x,y,xw,yh);
    return new float[]{round(tr[2] * cosa), round(tr[2] * sina), 1};
  }

  /**
   * redirect force-based trajectory along this boundary's surface.
   */
  float[] redirectForce(float x, float y, float fx, float fy) {
    float x1 = x, y1 = y, x2 = x+fx, y2 = y+fy;
    // Will this force illegally push the actor through the boundary?
    if (!onPassThroughSide(x1,y1,x2,y2)) {
      float[] tr = translateRotateXY3(x1,y1,x2,y2, x,y,xw,yh);
      float nx2 = tr[2];
      float ix = nx2 * cosa;
      float iy = nx2 * sina;
      return new float[]{ix, iy, 1};
    }
    // No it won't, pass-through the impulse unmodified.
    return new float[]{fx, fy, 0};
  }

  /**
   * Can this object be drawn in this viewbox?
   */
  boolean drawableFor(float vx, float vy, float vw, float vh) {
    // boundaries are invisible to begin with.
    return true;
  }

  /**
   * draw this platform
   */
  void drawObject() {
    strokeWeight(1);
    stroke(255, 0, 255);
    line(0, 0, dx, dy);

    // draw an arrow to indicate the pass-through direction
    stroke(127);
    float cs = cos(angle-PI/2), ss = sin(angle-PI/2);

    float fx = 10*cs;
    float fy = 10*ss;
    line((dx-fx)/2, (dy-fy)/2, dx/2 + fx, dy/2 + fy);

    float fx2 = 6*cs - 4*ss;
    float fy2 = 6*ss + 4*cs;
    line(dx/2+fx2, dy/2+fy2, dx/2 + fx, dy/2 + fy);

    fx2 = 6*cs + 4*ss;
    fy2 = 6*ss - 4*cs;
    line(dx/2+fx2, dy/2+fy2, dx/2 + fx, dy/2 + fy);
  }

  /**
   * Useful for debugging
   */
  String toString() { return x+","+y+","+xw+","+yh; }
}

