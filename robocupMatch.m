function results = robocupMatch(n, firstSeed, animate, halfLength)
%ROBOCUPMATCH  Full-pitch 4 v 4 robot football: Blue against Red.
%
%   robocupMatch                     ask how many matches to play
%   robocupMatch(1)                  watch one full match (2 x 10 min of game time)
%   robocupMatch(1, 7)               replay match 7 exactly (match k uses random seed k)
%   robocupMatch(1, 1, true, 120)    watch a short match with 2-minute halves
%   robocupMatch(50)                 play 50 matches without drawing (fast)
%   results = robocupMatch(20, 1, false)   no drawing, just return the results
%
%   One match is animated by default. Results are saved in a 'results' folder
%   next to this file: a summary table (CSV), the event logs (TXT), all
%   trajectories (MAT, every 0.2 s) and an overview picture (PNG).
%
%   Pitch as in the ENG5325 spec: 9 x 6 m, centre spot at (0, 0), goals 2.6 m
%   wide at x = -4.5 and +4.5, seen from above, in metres and seconds. Blue
%   attacks +x in the first half; the teams swap ends at half time.
%
%   Each team has a keeper and three field players whose roles are re-assigned
%   every step:
%     STRIKER    whoever can reach the ball soonest: takes control, then shoots,
%                passes, kicks long or dribbles. Tackles an opponent on the ball.
%     SUPPORTER  attacking: finds space ahead of the ball with a clear pass line.
%                Defending: marks the most dangerous opponent.
%     DEFENDER   stands between the ball and our goal, presses in our half.
%     KEEPER     slides along the goal line to where the ball will cross it,
%                comes out for slow balls, catches anything it touches in its
%                penalty area, then passes or kicks long.
%   A robot needs P.kickPrep seconds after taking control before it can kick.
%   A slow ball touching a robot is controlled, a fast one bounces off (checked
%   along the ball's whole path). An opponent touching the ball at a robot's
%   feet tackles it. Kick-offs, kick-ins, goal kicks and corners: the other
%   team keeps P.restartDist from the ball until it is kicked.

if nargin < 1 || isempty(n), n = 0; end
while ~(isnumeric(n) && isscalar(n) && n >= 1 && n == round(n))
    n = input('How many matches? ');
end
if nargin < 2 || isempty(firstSeed), firstSeed = 1; end
if nargin < 3 || isempty(animate), animate = (n == 1); end

%% Settings
P.dt = 0.05;           P.halfLength = 600;    % s
P.goalPause = 3;       P.restartTimeout = 20; % s
% pitch (ENG5325 spec, Table 1)
P.halfL = 4.5;         P.halfW = 3.0;         P.border = 1.0;        % m
P.goalHalfW = 1.3;     P.goalDepth = 0.6;                            % m
P.goalAreaL = 1.0;     P.goalAreaHalfW = 1.5;                        % m
P.penaltyL = 2.0;      P.penaltyHalfW = 2.5;  P.penaltyMark = 1.5;   % m
P.circleR = 0.75;                                                    % m
% ball
P.ballR = 0.07;        P.friction = 0.3;      P.restitution = 0.3;   % m, m/s^2, fraction kept in a bounce
% robots
P.robotR = 0.15;       P.walkV = 0.25;        P.dribbleV = 0.18;     % m, m/s, m/s
P.turnRate = 3;        P.dribbleTurn = 1;                            % rad/s
P.keeperX = 4.3;       P.keeperV = 0.3;       P.keeperR = 0.25;      % m, m/s, m (reach in own penalty area)
P.keeperDelay = 0.15;  P.keeperHold = 1.5;    % s, reaction after a kick; holding before distributing
P.controlSpeed = 1.0;  % m/s, a robot can only control a ball slower than this
P.kickPrep = 0.5;      % s, time to turn and set up a kick after taking control
P.kickGrace = 0.3;     % s, a kicked ball can't touch the kicker again for this long
P.maxHold = 4;         % s, after holding this long a robot passes or shoots more readily
P.shotSpeed = 2.2;     P.shotNoise = 0.08;    % m/s, rad
P.passNoise = 0.05;    P.passArrive = 0.4;    P.maxPassDist = 5;     % rad, m/s at the team-mate, m
P.longKick = 4;        P.longNoise = 0.2;     % m, rad
P.aimInside = 0.35;    % m, aim at least this far inside the posts
P.tackleSpeed = 0.8;   P.stunTime = 1.0;      % m/s, s to recover after being tackled
P.restartDist = 0.75;  % m
P.roleHysteresis = 1;  % s, the striker keeps its role unless another robot is this much quicker
% decisions
P.shootRange = 3.0;    % m, shoot from closer than this
P.shotClear = 0.4;     % m, shoot when nobody is this close to the shot line
P.laneClear = 0.6;     % m, pass when nobody is this close to the pass line
P.passGain = 0.8;      % m, only pass forward this far (unless under pressure)
P.pressureDist = 0.6;  % m, an opponent this close to the ball: act now
P.supportAhead = 1.8;  % m, where the supporter looks for space ahead of the ball
P.pressDist = 1.2;     % m, the defender presses a ball this close in our half
% output
P.names = {'Blue', 'Red'};  P.colours = [0.15 0.45 1; 0.9 0.2 0.2];
P.recordEvery = 4;     P.drawEvery = 2;       % store every 4th step, draw every 2nd
if nargin >= 4 && ~isempty(halfLength), P.halfLength = halfLength; end

%% Play
results = [];
for k = 1:n
    r = playMatch(P, firstSeed + k - 1, animate);
    results = [results; r]; %#ok<AGROW>
    fprintf('Match %3d:  Blue %d - %d Red   shots %2d-%-2d  passes %2d/%-2d %2d/%-2d  possession %2.0f%%-%2.0f%%\n', ...
        r.Match, r.BlueGoals, r.RedGoals, r.Blue.shots, r.Red.shots, r.Blue.passesCompleted, ...
        r.Blue.passes, r.Red.passesCompleted, r.Red.passes, r.Blue.possession, r.Red.possession);
end
bg = [results.BlueGoals];  rg = [results.RedGoals];
fprintf('\nBlue wins %d   draws %d   Red wins %d\n', sum(bg > rg), sum(bg == rg), sum(bg < rg));
folder = saveResults(results, P);
fprintf('Results saved in %s\n', folder);
end


%% ------------------------------------------------------------------
function r = playMatch(P, seed, animate)
rng(seed);                                   % same seed = same match
for i = 1:8                                  % robots 1-4 Blue, 5-8 Red, number 1 is the keeper
    W.rob(i) = struct('team', 1 + (i > 4), 'num', i - 4 * (i > 4), 'isKeeper', any(i == [1 5]), ...
        'pos', [0 0], 'heading', [1 0], 'role', '', 'held', 0, 'stunUntil', -inf);
end
stats = struct('shots', 0, 'onTarget', 0, 'passes', 0, 'passesCompleted', 0, ...
    'tackles', 0, 'saves', 0, 'possession', 0);
for k = 1:2
    W.team(k) = struct('name', P.names{k}, 'score', 0, 'dir', 3 - 2 * k, 'striker', 0, ...
        'receiver', 0, 'receiverUntil', -inf, 'stats', stats);
end
W.t = 0;  W.events = {};
W.ball = struct('pos', [0 0], 'vel', [0 0], 'owner', 0, 'lastKicker', 0, 'lastKickT', -inf, 'lastTouchTeam', 0);
W.lastControlTeam = 0;
W.state = 'KICKOFF';  W.restartTeam = 1;  W.stateStart = 0;  W.half = 1;
W.pendingPass = [0 0 0];                     % [team passer receiver] of a pass on its way
W.pendingShot = 0;                           % row in shotLog of a shot on its way
W.shotLog = zeros(0, 4);                     % [team x y outcome], x y as seen by the shooter
firstKickoff = 1 + (rand < 0.5);
W = setupKickoff(W, P, firstKickoff);

N = round((2 * P.halfLength + 4 * P.goalPause) / P.dt);
M = ceil(N / P.recordEvery) + 1;  m = 0;
ballTrack = nan(M, 2, 'single');  robTrack = nan(M, 2, 8, 'single');
if animate, H = initScene(P, W); end
for step = 1:N
    W.t = (step - 1) * P.dt;
    % game clock: kick-off after a goal, set-play timeout, half time, full time
    if strcmp(W.state, 'GOALPAUSE') && W.t - W.stateStart >= P.goalPause
        W = setupKickoff(W, P, W.restartTeam);
    elseif isSetPlay(W) && W.t - W.stateStart > P.restartTimeout
        W.state = 'PLAYING';  W = logEvent(W, 'Set play not taken in time: ball in play');
    end
    if ~strcmp(W.state, 'GOALPAUSE') && W.t >= W.half * P.halfLength
        if W.half == 2, W = logEvent(W, 'FULL TIME   %s', scoreLine(W)); break; end
        W.half = 2;  W = logEvent(W, 'HALF TIME   %s', scoreLine(W));
        W.team(1).dir = -W.team(1).dir;  W.team(2).dir = -W.team(2).dir;   % swap ends
        W = setupKickoff(W, P, 3 - firstKickoff);
    end

    if ~strcmp(W.state, 'GOALPAUSE')
        old.ball = W.ball;  old.pos = robotPositions(W, 1:8);
        W = assignRoles(W, P, 1);  W = assignRoles(W, P, 2);   % 1. who does what
        order = 1:8;  if mod(step, 2) == 0, order = [5:8 1:4]; end   % take turns going first
        for i = order                                          % 2. everyone decides and moves
            if W.rob(i).isKeeper, W = keeperStep(W, P, i); else, W = fieldPlayerStep(W, P, i); end
        end
        W = keepApart(W, P);                                   % 3. no overlaps, set-play distance
        W = moveBall(W, P, true);                              % 4. ball at feet, or rolling
        W = resolve(W, old, P);                                % 5. tackles, touches, goals, ball out
        W = moveBall(W, P, false);
        k = W.lastControlTeam;  if W.ball.owner > 0, k = W.rob(W.ball.owner).team; end
        if k > 0 && strcmp(W.state, 'PLAYING')
            W.team(k).stats.possession = W.team(k).stats.possession + P.dt;
        end
    end
    if mod(step - 1, P.recordEvery) == 0
        m = m + 1;  ballTrack(m, :) = W.ball.pos;
        robTrack(m, :, :) = reshape(robotPositions(W, 1:8)', 1, 2, 8);
    end
    if animate && mod(step, P.drawEvery) == 0
        if ishandle(H.fig), updateScene(H, W, P, ballTrack(max(1, m - 40):m, :));
        else, animate = false; end           % window closed: carry on without drawing
    end
end
if animate && ishandle(H.fig), updateScene(H, W, P, ballTrack(max(1, m - 40):m, :)); end

r.Match = seed;  r.BlueGoals = W.team(1).score;  r.RedGoals = W.team(2).score;
total = max(W.team(1).stats.possession + W.team(2).stats.possession, eps);
for k = 1:2, W.team(k).stats.possession = 100 * W.team(k).stats.possession / total; end   % percent
r.Blue = W.team(1).stats;  r.Red = W.team(2).stats;
r.Shots = W.shotLog;   r.Events = W.events;
r.ball = ballTrack(1:m, :);  r.robots = robTrack(1:m, :, :);   % time x [x y] (x robot)
end


%% ------------------------------------------------------------------
function W = setupKickoff(W, P, k)
% Both teams line up in their own half (as if they had walked there)
form = [-P.keeperX 0; -3.0 0; -1.5 1.2; -1.0 0];    % keeper, defender, supporter, striker
roles = {'KEEPER', 'DEFENDER', 'SUPPORTER', 'STRIKER'};
for kk = 1:2
    s = W.team(kk).dir;  f = form;
    if kk == k, f(3, :) = [-1.0 1.4];  f(4, :) = [-0.3 0]; end   % kicking team: striker at the ball
    if rand < 0.5, f(3, 2) = -f(3, 2); end
    for j = 1:4
        i = (kk - 1) * 4 + j;
        W.rob(i).pos = s * (f(j, :) + (j > 1) * 0.1 * randn(1, 2));
        W.rob(i).heading = [s 0];  W.rob(i).role = roles{j};
        W.rob(i).held = 0;  W.rob(i).stunUntil = -inf;
    end
    W.team(kk).striker = (kk - 1) * 4 + 4;  W.team(kk).receiver = 0;
end
W.ball.pos = [0 0];  W.ball.vel = [0 0];  W.ball.owner = 0;  W.ball.lastKicker = 0;  W.ball.lastTouchTeam = 0;
W.pendingPass = [0 0 0];  W.pendingShot = 0;
W.state = 'KICKOFF';  W.restartTeam = k;  W.stateStart = W.t;
W = logEvent(W, 'KICK-OFF %s', W.team(k).name);
end


function W = startRestart(W, P, type, k, spot)
W.ball.pos = spot;  W.ball.vel = [0 0];  W.ball.owner = 0;
W.state = type;  W.restartTeam = k;  W.stateStart = W.t;
if W.pendingShot > 0, W.shotLog(W.pendingShot, 4) = 4; end   % the shot missed
W.pendingShot = 0;  W.pendingPass = [0 0 0];  W.team(1).receiver = 0;  W.team(2).receiver = 0;
W = logEvent(W, '%s for %s at (%.1f, %.1f)', type, W.team(k).name, spot(1), spot(2));
end


function ok = isSetPlay(W)
ok = any(strcmp(W.state, {'KICKOFF', 'KICK-IN', 'GOAL KICK', 'CORNER'}));
end


%% ------------------------------------------------------------------
function W = assignRoles(W, P, k)
idx = (k - 1) * 4 + (2:4);  b = W.ball;  T = W.team(k);  s = T.dir;
if b.owner > 0 && W.rob(b.owner).team == k && ~W.rob(b.owner).isKeeper
    striker = b.owner;                       % whoever has the ball
elseif T.receiver > 0 && b.owner == 0 && W.t < T.receiverUntil
    striker = T.receiver;                    % a pass is on its way to this robot
else                                         % otherwise whoever can reach the ball soonest
    cost = zeros(1, 3);
    for j = 1:3
        r = W.rob(idx(j));
        cost(j) = norm(interceptPoint(b, r.pos, P) - r.pos) / P.walkV ...
            + 2 * (s * (r.pos(1) - b.pos(1)) > 0.3) ...     % on the wrong side of the ball
            + 10 * (W.t < r.stunUntil) - P.roleHysteresis * (idx(j) == T.striker);
    end
    [~, j] = min(cost);  striker = idx(j);
end
% the other two share defender and supporter so that they walk the least
o = idx(idx ~= striker);  bT = s * b.pos;  g = [-P.halfL 0];
dSpot = s * (g + min(max(0.45 * norm(bT - g), 1.3), 3.2) * unit(bT - g));
sSpot = s * [min(bT(1) + 1.5, P.halfL - 1.2), -0.5 * bT(2)];
c1 = norm(W.rob(o(1)).pos - dSpot) + norm(W.rob(o(2)).pos - sSpot) - 0.5 * strcmp(W.rob(o(1)).role, 'DEFENDER');
c2 = norm(W.rob(o(2)).pos - dSpot) + norm(W.rob(o(1)).pos - sSpot) - 0.5 * strcmp(W.rob(o(2)).role, 'DEFENDER');
if c2 < c1, o = o([2 1]); end
W.rob(striker).role = 'STRIKER';  W.rob(o(1)).role = 'DEFENDER';  W.rob(o(2)).role = 'SUPPORTER';
W.team(k).striker = striker;
end


%% ------------------------------------------------------------------
function W = fieldPlayerStep(W, P, i)
r = W.rob(i);  k = r.team;  s = W.team(k).dir;  b = W.ball;
if W.t < r.stunUntil, return; end            % recovering from a tackle
if b.owner == i, W = ownerAct(W, P, i); return; end
bT = s * b.pos;  g = [-P.halfL 0];           % team frame: we attack +x
theirSetPlay = isSetPlay(W) && W.restartTeam ~= k;
ours = b.owner > 0 && W.rob(b.owner).team == k;   % only happens when our keeper has it
switch r.role
    case 'STRIKER'
        if theirSetPlay, target = s * (bT + (P.restartDist + 0.15) * unit(g - bT));   % between ball and our goal
        elseif ours,     target = supportSpot(W, P, i);                              % get free for a pass
        else,            target = interceptPoint(b, r.pos, P);
        end
    case 'DEFENDER'
        if ours                              % out of the keeper's way, wide for a pass
            target = s * [-P.halfL + 1.8, -1.8 * sign(bT(2) + 1e-6)];
        elseif ~theirSetPlay && bT(1) < 0 && norm(b.pos - r.pos) < P.pressDist
            target = interceptPoint(b, r.pos, P);   % press
        else                                 % between the ball and our goal, in our half
            p = g + min(max(0.45 * norm(bT - g), 1.3), 3.2) * unit(bT - g);
            target = s * [min(p(1), -0.5), p(2)];
        end
    otherwise
        target = supportSpot(W, P, i);
end
W = moveRobot(W, P, i, target, P.walkV);
W = tryControl(W, P, i, false);
end


function W = ownerAct(W, P, i)
% The robot has the ball: shoot, pass, kick long or dribble (team frame: we attack +x)
r = W.rob(i);  k = r.team;  s = W.team(k).dir;
W.rob(i).held = r.held + P.dt;  held = W.rob(i).held;
bT = s * W.ball.pos;  goal = [P.halfL 0];  dGoal = norm(goal - bT);
oppT = s * robotPositions(W, (2 - k) * 4 + (1:4));
others = s * robotPositions(W, setdiff(1:8, i));   % any robot can block the ball
pressure = min(sqrt(sum((oppT - bT).^2, 2))) < P.pressureDist;
canShoot = ~strcmp(W.state, 'KICKOFF');
if held < P.kickPrep                         % turning and setting up
    W.rob(i).heading = rotateTowards(r.heading, s * unit(goal - bT), pi / P.kickPrep * P.dt);
    return;
end
ys = linspace(-1, 1, 9)' * (P.goalHalfW - P.aimInside);
[aim, clearance] = clearestSpot(bT, [P.halfL + 0 * ys, ys], others, 0.01 * abs(ys));
if canShoot && dGoal < P.shootRange && (clearance > P.shotClear || pressure || held > P.maxHold)
    W = kickBall(W, P, i, aim, P.shotSpeed, P.shotNoise, 'SHOT');
    return;
end
[mate, tgt, gain, lane] = bestPass(W, P, i);
urgent = pressure || isSetPlay(W) || held > P.maxHold;
if mate > 0 && ((gain > P.passGain && lane > P.laneClear) || (urgent && lane > P.laneClear / 2))
    W = kickBall(W, P, i, tgt, sqrt(P.passArrive^2 + 2 * P.friction * norm(tgt - bT)), P.passNoise, 'PASS', mate);
    return;
end
if isSetPlay(W) || held > 3 * P.maxHold || (pressure && (bT(1) < 0 || dGoal < 1.3 * P.shootRange))
    if canShoot && dGoal < 1.3 * P.shootRange
        W = kickBall(W, P, i, aim, P.shotSpeed, P.shotNoise, 'SHOT');
    else
        W = longKick(W, P, i, others);
    end
    return;
end
% dribble towards goal, steering away from opponents in front
dirG = unit(goal - bT);  side = [-dirG(2) dirG(1)];  push = [0 0];
for o = 1:4
    d = oppT(o, :) - bT;
    if norm(d) < 1.5 && dot(d, dirG) > -0.2
        push = push - (2 * (dot(d, side) >= 0) - 1) * side * (1.5 - norm(d));
    end
end
target = bT + unit(dirG + push);
target = [min(target(1), P.halfL - 0.4), clamp(target(2), P.halfW - 0.4)];
W.rob(i).heading = rotateTowards(r.heading, s * unit(target - bT), P.dribbleTurn * P.dt);
W = moveRobot(W, P, i, r.pos + W.rob(i).heading, P.dribbleV);
end


function W = keeperStep(W, P, i)
r = W.rob(i);  k = r.team;  s = W.team(k).dir;  b = W.ball;
bT = s * b.pos;  vT = s * b.vel;  xK = -P.keeperX;
if b.owner == i                              % holding the ball: pass, or kick it long
    W.rob(i).held = r.held + P.dt;
    if W.rob(i).held >= P.keeperHold
        [mate, tgt, ~, lane] = bestPass(W, P, i);
        if mate > 0 && lane > P.laneClear
            W = kickBall(W, P, i, tgt, sqrt(P.passArrive^2 + 2 * P.friction * norm(tgt - bT)), P.passNoise, 'PASS', mate);
        else
            W = longKick(W, P, i, s * robotPositions(W, setdiff(1:8, i)));
        end
    end
    return;
end
oppT = s * robotPositions(W, (2 - k) * 4 + (1:4));
nearestOpp = min(sqrt(sum((oppT - bT).^2, 2)));
v = P.keeperV;
if ~(isSetPlay(W) && W.restartTeam ~= k) && b.owner == 0 && inBox(bT, P) && norm(b.vel) < 0.6 ...
        && norm(bT - s * r.pos) < nearestOpp - 0.2
    target = bT;  v = P.walkV;               % come out for a slow ball
elseif b.owner == 0 && vT(1) < -0.1 && bT(1) > xK && W.t >= b.lastKickT + P.keeperDelay
    target = [xK, clamp(bT(2) + vT(2) * (xK - bT(1)) / vT(1), P.goalHalfW)];   % where it crosses our line
else
    target = [xK, clamp(0.4 * bT(2), P.goalHalfW - 0.3)];   % shade towards the ball
end
W = moveRobot(W, P, i, s * target, v);
W = tryControl(W, P, i, false);
end


%% ------------------------------------------------------------------
function spot = supportSpot(W, P, i)
k = W.rob(i).team;  s = W.team(k).dir;  bT = s * W.ball.pos;  g = [-P.halfL 0];  own = W.ball.owner;
if (own > 0 && W.rob(own).team == k) || (own == 0 && W.lastControlTeam == k)
    % attacking: space ahead of the ball with a clear pass line, away from the striker
    [X, Y] = meshgrid(min(max(bT(1) + P.supportAhead + [-0.8 0 0.8], -2.5), P.halfL - 1.2), -2.4:0.6:2.4);
    C = [X(:) Y(:)];
    meT = s * W.rob(i).pos;  stT = s * W.rob(W.team(k).striker).pos;
    penalty = 0.12 * abs(C(:, 2)) + 0.25 * abs(C(:, 1) - bT(1) - P.supportAhead) ...
        - 0.15 * (sqrt(sum((C - meT).^2, 2)) < 0.4);   % don't change our mind for nothing
    if W.team(k).striker ~= i, penalty = penalty + 1.5 * (sqrt(sum((C - stT).^2, 2)) < 1.2); end
    spot = clearestSpot(bT, C, s * robotPositions(W, (2 - k) * 4 + (1:4)), penalty);
else
    % defending: mark the opponent field player nearest our goal, or screen our defence
    spot = [(bT(1) + g(1)) / 2 + 0.8, 0.5 * bT(2)];  best = inf;
    for j = (2 - k) * 4 + (2:4)
        o = s * W.rob(j).pos;
        if j ~= own && o(1) < 1 && norm(o - g) < best, best = norm(o - g);  spot = o + 0.6 * unit(g - o); end
    end
end
spot = s * [clamp(spot(1), P.halfL - 0.5), clamp(spot(2), P.halfW - 0.3)];
end


function [spot, clearance] = clearestSpot(from, C, obstacles, penalty)
% Of the candidate points C (one per row), the one whose line from 'from'
% stays furthest from every obstacle (counted up to 1.5 m), minus a penalty
clr = inf(size(C, 1), 1);
for c = 1:size(C, 1)
    for o = 1:size(obstacles, 1), clr(c) = min(clr(c), laneClearance(from, C(c, :), obstacles(o, :))); end
end
[~, c] = max(min(clr, 1.5) - penalty);
spot = C(c, :);  clearance = clr(c);
end


function [mate, tgt, gain, lane] = bestPass(W, P, i)
% Best field team-mate to pass to (team frame): forward progress plus a clear lane
k = W.rob(i).team;  s = W.team(k).dir;  bT = s * W.ball.pos;
mate = 0;  tgt = [0 0];  gain = -inf;  lane = 0;  best = -inf;
for j = (k - 1) * 4 + (2:4)
    if j == i || W.t < W.rob(j).stunUntil, continue; end
    t = s * W.rob(j).pos + [0.3 0];          % just ahead of the team-mate
    t = [clamp(t(1), P.halfL - 0.3), clamp(t(2), P.halfW - 0.3)];
    if norm(t - bT) < 0.8 || norm(t - bT) > P.maxPassDist, continue; end
    ln = inf;
    for q = setdiff(1:8, [i j])              % anyone in the way, and opponents near the receiver
        p = s * W.rob(q).pos;
        ln = min(ln, laneClearance(bT, t, p));
        if W.rob(q).team ~= k, ln = min(ln, norm(p - t)); end
    end
    if t(1) - bT(1) + 0.8 * min(ln, 1.5) > best
        best = t(1) - bT(1) + 0.8 * min(ln, 1.5);  mate = j;  tgt = t;  gain = t(1) - bT(1);  lane = ln;
    end
end
end


function W = longKick(W, P, i, others)
% Kick into the space up the pitch whose line is clearest
s = W.team(W.rob(i).team).dir;  bT = s * W.ball.pos;  ys = (-2.4:0.6:2.4)';
tgt = clearestSpot(bT, [min(bT(1) + P.longKick, P.halfL - 0.5) + 0 * ys, ys], others, 0.1 * abs(ys));
W = kickBall(W, P, i, tgt, sqrt(2 * P.friction * norm(tgt - bT)), P.longNoise, 'LONG');
end


%% ------------------------------------------------------------------
function W = kickBall(W, P, i, targetT, speed, noise, type, mate)
k = W.rob(i).team;  s = W.team(k).dir;
d = s * targetT - W.rob(i).pos;
a = atan2(d(2), d(1)) + noise * randn;  dir = [cos(a) sin(a)];
if ~strcmp(type, 'SHOT'), speed = speed * (1 + 0.1 * randn); end
% the robot turned to face the kick during kickPrep, so the ball starts on
% that side of it and never rolls back through the kicker's own body
W.rob(i).heading = dir;  W.rob(i).held = 0;
W.ball.pos = W.rob(i).pos + (contactRadius(W, P, i) + 0.01) * dir;
W.ball.vel = speed * dir;  W.ball.owner = 0;
W.ball.lastKicker = i;  W.ball.lastKickT = W.t;  W.ball.lastTouchTeam = k;
if strcmp(type, 'SHOT')
    W.team(k).stats.shots = W.team(k).stats.shots + 1;
    W.shotLog(end + 1, :) = [k s * W.ball.pos 0];  W.pendingShot = size(W.shotLog, 1);
    W = logEvent(W, '%s SHOOTS from %.1f m', robotName(W, i), norm([P.halfL 0] - s * W.ball.pos));
elseif strcmp(type, 'PASS')
    W.team(k).stats.passes = W.team(k).stats.passes + 1;
    W.pendingPass = [k i mate];
    W.team(k).receiver = mate;  W.team(k).receiverUntil = W.t + norm(d) / speed + 2;
    W = logEvent(W, '%s passes to %s', robotName(W, i), robotName(W, mate));
else
    W = logEvent(W, '%s kicks it long', robotName(W, i));
end
if isSetPlay(W), W.state = 'PLAYING'; end    % the ball is in play once kicked
end


function W = tryControl(W, P, i, touching)
% Take control of a free ball: always for a keeper in its own penalty area,
% otherwise only a slow one. Also keeps track of passes and shots.
r = W.rob(i);  k = r.team;  b = W.ball;
keeperInBox = r.isKeeper && inBox(W.team(k).dir * r.pos, P);
allowed = strcmp(W.state, 'PLAYING') || (isSetPlay(W) && k == W.restartTeam);
if b.owner > 0 || W.t < r.stunUntil || ~allowed || (b.lastKicker == i && W.t - b.lastKickT < P.kickGrace) ...
        || (~touching && norm(r.pos - b.pos) > contactRadius(W, P, i) + 0.03) ...
        || (~keeperInBox && norm(b.vel) > P.controlSpeed)
    return;
end
speed = norm(b.vel);  wasTeam = W.lastControlTeam;  msg = '';
W.ball.owner = i;  W.ball.vel = [0 0];  W.ball.lastTouchTeam = k;  W.lastControlTeam = k;
W.rob(i).held = 0;  W.rob(i).heading = unit(b.pos - r.pos);  W.team(k).receiver = 0;
if W.pendingPass(1) == k && W.pendingPass(2) ~= i
    W.team(k).stats.passesCompleted = W.team(k).stats.passesCompleted + 1;  msg = 'receives the pass';
elseif W.pendingPass(1) > 0 && W.pendingPass(1) ~= k
    msg = 'intercepts the pass';
end
W.pendingPass = [0 0 0];
if W.pendingShot > 0
    if r.isKeeper && W.shotLog(W.pendingShot, 1) ~= k && speed > 0.3
        W.shotLog(W.pendingShot, 4) = 2;  msg = 'SAVES';
        W.team(k).stats.saves = W.team(k).stats.saves + 1;
        W.team(3 - k).stats.onTarget = W.team(3 - k).stats.onTarget + 1;
    else
        W.shotLog(W.pendingShot, 4) = 4;     % the shot went astray
    end
    W.pendingShot = 0;
end
if isempty(msg) && wasTeam ~= k, msg = 'wins the ball'; end
if ~isempty(msg), W = logEvent(W, '%s %s', robotName(W, i), msg); end
end


%% ------------------------------------------------------------------
function W = moveRobot(W, P, i, target, v)
% Straight line, at most speed v, never overshooting; stay on the pitch or border
r = W.rob(i);  d = target - r.pos;
if norm(d) > 1e-9
    p = r.pos + min(norm(d), v * P.dt) * unit(d);
    W.rob(i).pos = [clamp(p(1), P.halfL + P.border - 0.2), clamp(p(2), P.halfW + P.border - 0.2)];
    if norm(d) > 0.05 && W.ball.owner ~= i
        W.rob(i).heading = rotateTowards(r.heading, unit(d), P.turnRate * P.dt);
    end
end
end


function W = keepApart(W, P)
for a = 1:7                                  % robots can't overlap
    for c = a + 1:8
        d = W.rob(c).pos - W.rob(a).pos;
        if norm(d) < 2 * P.robotR
            push = (2 * P.robotR - norm(d)) / 2 * unit(d);
            W.rob(a).pos = W.rob(a).pos - push;  W.rob(c).pos = W.rob(c).pos + push;
        end
    end
end
if ~isSetPlay(W), return; end
for i = 1:8                                  % set play: the other team keeps its distance
    k = W.rob(i).team;
    if strcmp(W.state, 'KICKOFF') && ~(k == W.restartTeam && strcmp(W.rob(i).role, 'STRIKER'))
        s = W.team(k).dir;                   % and everyone stays in their own half at kick-off
        if s * W.rob(i).pos(1) > -P.robotR, W.rob(i).pos(1) = -s * P.robotR; end
    end
    d = W.rob(i).pos - W.ball.pos;
    if k ~= W.restartTeam && norm(d) < P.restartDist, W.rob(i).pos = W.ball.pos + P.restartDist * unit(d); end
end
end


function W = moveBall(W, P, roll)
o = W.ball.owner;
if o > 0                                     % at the owner's feet
    W.ball.pos = W.rob(o).pos + (P.robotR + P.ballR) * W.rob(o).heading;  W.ball.vel = [0 0];
elseif roll                                  % rolling and slowing down
    speed = norm(W.ball.vel);
    if speed > 0, W.ball.vel = W.ball.vel * max(speed - P.friction * P.dt, 0) / speed; end
    W.ball.pos = W.ball.pos + W.ball.vel * P.dt;
end
end


function W = resolve(W, old, P)
b = W.ball;
if b.owner > 0
    % tackle: an opponent touching the ball at a robot's feet knocks it loose
    o = b.owner;  k = W.rob(o).team;
    if ~strcmp(W.state, 'PLAYING') || (W.rob(o).isKeeper && inBox(W.team(k).dir * W.rob(o).pos, P)), return; end
    for j = (2 - k) * 4 + (1:4)
        if W.t >= W.rob(j).stunUntil && norm(W.rob(j).pos - b.pos) <= P.robotR + P.ballR + 0.01
            d = unit(unit(b.pos - W.rob(j).pos) + 0.7 * [W.team(3 - k).dir 0]);
            a = atan2(d(2), d(1)) + 0.4 * randn;
            W.ball.owner = 0;  W.ball.vel = P.tackleSpeed * [cos(a) sin(a)];
            W.ball.lastKicker = j;  W.ball.lastKickT = W.t;  W.ball.lastTouchTeam = 3 - k;
            W.rob(o).stunUntil = W.t + P.stunTime;
            W.team(3 - k).stats.tackles = W.team(3 - k).stats.tackles + 1;
            W = logEvent(W, '%s tackles %s', robotName(W, j), robotName(W, o));
            return;
        end
    end
    return;
end
% free ball: what did it touch or cross first during this step?
b0 = old.ball.pos;  b1 = b.pos;  aRob = inf(1, 8);
for j = 1:8
    if ~(j == b.lastKicker && W.t - b.lastKickT < P.kickGrace)
        aRob(j) = contactTime(b0 - old.pos(j, :), b1 - W.rob(j).pos, contactRadius(W, P, j));
    end
end
[aR, j] = min(aRob);
lineX = P.halfL + P.ballR;  lineY = P.halfW + P.ballR;   % whole ball over the line
aG = inf;  aS = inf;  gSide = 0;
for side = [-1 1]
    if side * b0(1) < lineX && side * b1(1) >= lineX, aG = (lineX - side * b0(1)) / (side * (b1(1) - b0(1)));  gSide = side; end
    if side * b0(2) < lineY && side * b1(2) >= lineY, aS = (lineY - side * b0(2)) / (side * (b1(2) - b0(2))); end
end
first = min([aR aG aS]);
if ~isfinite(first), return; end
W.ball.pos = b0 + first * (b1 - b0);         % back to where it happened
y = W.ball.pos(2);
if aR == first
    % a robot: controls the ball if it can, otherwise the ball bounces off it
    W2 = tryControl(W, P, j, true);
    if W2.ball.owner == j, W = W2; return; end
    k = W.rob(j).team;  rv = (W.rob(j).pos - old.pos(j, :)) / P.dt;
    nrm = unit(W.ball.pos - (old.pos(j, :) + first * rv * P.dt));
    vr = W.ball.vel - rv;
    if dot(vr, nrm) < 0, vr = vr - (1 + P.restitution) * dot(vr, nrm) * nrm; end
    W.ball.vel = vr + rv;
    W.ball.pos = W.rob(j).pos + (contactRadius(W, P, j) + 1e-3) * nrm;
    W.ball.lastKicker = j;  W.ball.lastKickT = W.t;  W.ball.lastTouchTeam = k;
    if W.pendingShot > 0 && W.shotLog(W.pendingShot, 1) ~= k
        W.shotLog(W.pendingShot, 4) = 3;  W.pendingShot = 0;
        W = logEvent(W, '%s blocks the shot', robotName(W, j));
    end
    if W.pendingPass(1) > 0 && W.pendingPass(1) ~= k
        W.pendingPass = [0 0 0];  W.team(3 - k).receiver = 0;
        W = logEvent(W, '%s cuts out the pass', robotName(W, j));
    end
elseif aG == first
    att = find([W.team.dir] == gSide);  def = 3 - att;   % att attacks the goal at this end
    if abs(y) < P.goalHalfW
        W.team(att).score = W.team(att).score + 1;
        if W.pendingShot > 0 && W.shotLog(W.pendingShot, 1) == att
            W.shotLog(W.pendingShot, 4) = 1;
            W.team(att).stats.onTarget = W.team(att).stats.onTarget + 1;
        end
        who = W.team(att).name;
        if b.lastKicker > 0, who = robotName(W, b.lastKicker); end
        if b.lastKicker > 0 && W.rob(b.lastKicker).team == def, who = ['own goal by ' who]; end
        W = logEvent(W, 'GOAL! %s   %s', who, scoreLine(W));
        W.ball.vel = [0 0];  W.ball.pos(1) = gSide * (P.halfL + 0.3);   % in the net
        W.pendingShot = 0;  W.pendingPass = [0 0 0];
        W.state = 'GOALPAUSE';  W.restartTeam = def;  W.stateStart = W.t;
    elseif W.ball.lastTouchTeam == def
        W = startRestart(W, P, 'CORNER', att, [gSide * P.halfL, sign(y) * P.halfW]);
    else
        W = startRestart(W, P, 'GOAL KICK', def, [gSide * (P.halfL - P.goalAreaL), sign(y) * P.goalAreaHalfW]);
    end
else
    k = 3 - W.ball.lastTouchTeam;  if k == 3, k = 1; end
    W = startRestart(W, P, 'KICK-IN', k, [clamp(W.ball.pos(1), P.halfL - 0.5), sign(y) * P.halfW]);
end
end


%% ------------------------------------------------------------------
%  Small helpers
function q = interceptPoint(b, p, P)
% Earliest point on the ball's rolling path that a robot at p can walk to in time
v0 = norm(b.vel);  q = b.pos;
if v0 < 0.05, return; end
tStop = v0 / P.friction;
for tau = [0:0.2:6, tStop]
    te = min(tau, tStop);
    q = b.pos + b.vel / v0 * (v0 * te - 0.5 * P.friction * te^2);
    if norm(q - p) <= P.walkV * tau + P.robotR, return; end
end
end

function rad = contactRadius(W, P, i)
% Ball centre to robot centre at a touch (the keeper reaches further in its own penalty area)
r = W.rob(i);  rad = P.robotR + P.ballR;
if r.isKeeper && inBox(W.team(r.team).dir * r.pos, P), rad = P.keeperR + P.ballR; end
end

function ok = inBox(pT, P)
% Is this point (team frame) in our own penalty area?
ok = pT(1) < -P.halfL + P.penaltyL && abs(pT(2)) < P.penaltyHalfW;
end

function pos = robotPositions(W, idx)
pos = reshape([W.rob(idx).pos], 2, [])';
end

function c = laneClearance(from, to, p)
% Shortest distance from point p to the line from -> to
d = to - from;
s = max(0, min(1, dot(p - from, d) / max(dot(d, d), 1e-12)));
c = norm(p - (from + s * d));
end

function alpha = contactTime(a, b, radius)
% The ball moves from a to b relative to a robot during one step. Returns
% the fraction of the step (0 to 1) when it first touches, or inf.
alpha = inf;
if dot(a, a) <= radius^2, alpha = 0; return; end
v = b - a;  A = dot(v, v);  B = 2 * dot(a, v);  C = dot(a, a) - radius^2;
disc = B^2 - 4 * A * C;
if A < 1e-12 || disc < 0, return; end
root = (-B - sqrt(disc)) / (2 * A);
if root >= 0 && root <= 1, alpha = root; end
end

function h = rotateTowards(h, d, maxAngle)
a = atan2(h(2), h(1));
da = mod(atan2(d(2), d(1)) - a + pi, 2 * pi) - pi;
a = a + max(min(da, maxAngle), -maxAngle);
h = [cos(a) sin(a)];
end

function y = clamp(y, limit)
y = max(min(y, limit), -limit);
end

function u = unit(v)
if norm(v) < 1e-10, u = [1 0]; else, u = v / norm(v); end
end

function s = robotName(W, i)
s = sprintf('%s %d', W.team(W.rob(i).team).name, W.rob(i).num);
end

function s = scoreLine(W)
s = sprintf('%s %d - %d %s', W.team(1).name, W.team(1).score, W.team(2).score, W.team(2).name);
end

function W = logEvent(W, fmt, varargin)
W.events{end + 1} = sprintf(['%02d:%04.1f  ' fmt], floor(W.t / 60), mod(W.t, 60), varargin{:});
end


%% ------------------------------------------------------------------
%  Saving and drawing
function folder = saveResults(results, P)
folder = fullfile(fileparts(mfilename('fullpath')), 'results');
if ~exist(folder, 'dir'), mkdir(folder); end
names = fieldnames(results(1).Blue);
fid = fopen(fullfile(folder, 'summary.csv'), 'w');
header = [names names]';
fprintf(fid, 'Match,BlueGoals,RedGoals%s\n', sprintf(',Blue_%s,Red_%s', header{:}));
for r = results'
    fprintf(fid, '%d,%d,%d', r.Match, r.BlueGoals, r.RedGoals);
    for j = 1:numel(names), fprintf(fid, ',%g,%g', round(10 * r.Blue.(names{j})) / 10, round(10 * r.Red.(names{j})) / 10); end
    fprintf(fid, '\n');
end
fclose(fid);
fid = fopen(fullfile(folder, 'events.txt'), 'w');
for r = results'
    fprintf(fid, 'Match %d: Blue %d - %d Red\n', r.Match, r.BlueGoals, r.RedGoals);
    fprintf(fid, '  %s\n', r.Events{:});
    fprintf(fid, '\n');
end
fclose(fid);
save(fullfile(folder, 'results.mat'), 'results', 'P', '-v7');

% overview: shot map, goals per match, average team statistics
fig = figure(2);  clf;  set(fig, 'Color', 'w', 'Position', [60 60 1400 520]);
subplot(1, 3, 1);  drawPitch(P, [0.4 0.4 0.4]);
marks = {'o', 's', '^', 'x'};
for r = results'
    for q = 1:size(r.Shots, 1)
        S = r.Shots(q, :);  oc = S(4) + 4 * (S(4) == 0);   % unresolved counts as missed
        if oc == 1, face = P.colours(S(1), :); else, face = 'none'; end
        plot(S(2), S(3), marks{oc}, 'Color', P.colours(S(1), :), 'MarkerFaceColor', face, 'MarkerSize', 6);
    end
end
h = zeros(1, 4);  for q = 1:4, h(q) = plot(nan, nan, marks{q}, 'Color', 'k'); end
legend(h, {'goal', 'saved', 'blocked', 'missed'}, 'Location', 'southwest');
title('Shots (both teams shown attacking \rightarrow)');
subplot(1, 3, 2);
hb = bar([[results.BlueGoals]' [results.RedGoals]'; nan nan], 'grouped');   % extra row: keeps 2 series for 1 match
xlim([0.5 numel(results) + 0.5]);
set(hb(1), 'FaceColor', P.colours(1, :));  set(hb(2), 'FaceColor', P.colours(2, :));
xlabel('match');  ylabel('goals');  title('Goals per match');  legend('Blue', 'Red');
subplot(1, 3, 3);
D = zeros(numel(names), 2);
for j = 1:numel(names)
    D(j, :) = [mean(arrayfun(@(r) r.Blue.(names{j}), results)), mean(arrayfun(@(r) r.Red.(names{j}), results))];
end
hb = barh(flipud(D), 'grouped');
set(hb(1), 'FaceColor', P.colours(1, :));  set(hb(2), 'FaceColor', P.colours(2, :));
set(gca, 'YTick', 1:numel(names), 'YTickLabel', flipud(names));
title('Average per match (possession in %)');
print(fig, fullfile(folder, 'overview.png'), '-dpng', '-r130');
end


function drawPitch(P, lc)
L = P.halfL;  Wd = P.halfW;  a = linspace(0, 2 * pi, 60);
hold on;
plot([-L L L -L -L], [-Wd -Wd Wd Wd -Wd], 'Color', lc);
plot([0 0], [-Wd Wd], 'Color', lc);  plot(P.circleR * cos(a), P.circleR * sin(a), 'Color', lc);
for sd = [-1 1]
    plot(sd * [L L - P.penaltyL L - P.penaltyL L], P.penaltyHalfW * [-1 -1 1 1], 'Color', lc);
    plot(sd * [L L - P.goalAreaL L - P.goalAreaL L], P.goalAreaHalfW * [-1 -1 1 1], 'Color', lc);
    plot(sd * [L L + P.goalDepth L + P.goalDepth L], P.goalHalfW * [-1 -1 1 1], 'Color', lc, 'LineWidth', 2.5);
    plot(sd * (L - P.penaltyMark), 0, '+', 'Color', lc);
end
axis equal;  axis([-L - P.border, L + P.border, -Wd - P.border, Wd + P.border]);
set(gca, 'XTick', [], 'YTick', []);  box on;
end


function H = initScene(P, W)
H.fig = figure(1);  clf;
set(H.fig, 'Color', [0.96 0.97 0.98], 'Position', [60 80 1380 640], 'Name', 'RoboCup 4 v 4');
axes('Position', [0.02 0.06 0.68 0.86]);
L = P.halfL + P.border;  Wd = P.halfW + P.border;
fill([-L L L -L], [-Wd -Wd Wd Wd], [0.10 0.42 0.22], 'EdgeColor', 'none');
drawPitch(P, 'w');
H.trail = plot(nan, nan, '-', 'Color', [1 0.85 0.3]);
H.a = linspace(0, 2 * pi, 24)';              % columns: patch data must be columns to update
for i = 1:8
    col = P.colours(W.rob(i).team, :) * (1 - 0.45 * W.rob(i).isKeeper);   % keepers darker
    H.body(i) = fill(P.robotR * cos(H.a), P.robotR * sin(H.a), col, 'EdgeColor', 'w');
    H.head(i) = plot([0 0], [0 0], 'w-', 'LineWidth', 2);
    H.num(i) = text(0, 0, num2str(W.rob(i).num), 'Color', 'w', 'FontSize', 8, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'center');
end
H.ball = fill(P.ballR * cos(H.a), P.ballR * sin(H.a), [1 0.6 0], 'EdgeColor', 'k');
H.title = title('', 'FontSize', 13);
axes('Position', [0.72 0.06 0.27 0.86], 'Visible', 'off');   % side panel
H.info = text(0, 1, '', 'VerticalAlignment', 'top', 'FontName', 'FixedWidth', 'FontSize', 9, 'Interpreter', 'none');
end


function updateScene(H, W, P, trail)
for i = 1:8
    p = W.rob(i).pos;  h = W.rob(i).heading;
    set(H.body(i), 'XData', p(1) + P.robotR * cos(H.a), 'YData', p(2) + P.robotR * sin(H.a));
    set(H.head(i), 'XData', p(1) + [0 0.25 * h(1)], 'YData', p(2) + [0 0.25 * h(2)]);
    set(H.num(i), 'Position', [p 0]);
end
set(H.ball, 'XData', W.ball.pos(1) + P.ballR * cos(H.a), 'YData', W.ball.pos(2) + P.ballR * sin(H.a));
set(H.trail, 'XData', trail(:, 1), 'YData', trail(:, 2));
set(H.title, 'String', sprintf('%s     %02d:%02d   half %d   %s', scoreLine(W), ...
    floor(W.t / 60), floor(mod(W.t, 60)), W.half, W.state));
attack = '+x';  if W.team(1).dir < 0, attack = '-x'; end
lines = {['Blue attacks ' attack]; ''};
for i = 1:8
    extra = '';
    if W.ball.owner == i, extra = ' (ball)'; end
    if W.t < W.rob(i).stunUntil, extra = ' (recovering)'; end
    lines{end + 1, 1} = sprintf('%-5s %d  %-9s%s', W.team(W.rob(i).team).name, W.rob(i).num, W.rob(i).role, extra); %#ok<AGROW>
end
lines = [lines; {''; 'EVENTS'}; W.events(max(1, end - 13):end)'];
set(H.info, 'String', strjoin(lines', char(10)));
drawnow;
end
