function outcomes = strikerVsKeeper(nShots)
%STRIKERVSKEEPER  One striker takes a penalty, one goalkeeper tries to save it.
%
%   strikerVsKeeper        ask what to do: watch one shot, or run a set
%                          number of shots and show the score
%   strikerVsKeeper(1)     watch one shot straight away
%   strikerVsKeeper(200)   run 200 shots without drawing and show the score
%
%   2D, seen from above. Units: metres and seconds.
%   x runs along the pitch, y across it. The goal line is at x = 4.5
%   and the goal is 2.6 m wide (Table 1 of the brief).
%
%   Every step of the simulation does three things:
%     1. the striker and the keeper decide and move
%     2. the ball rolls and slows down
%     3. we check for a goal, a save or a miss

if nargin < 1
    nShots = askUser();     % no number given: ask in the Command Window
end
watch = (nShots == 1);      % one shot = draw it, more than one = just count

%% Settings: change these and see what happens
P.dt          = 0.05;  % s, length of one step
P.maxTime     = 15;    % s, stop after this
P.goalX       = 4.5;   % m, goal line
P.goalHalfW   = 1.3;   % m, half the goal width
P.penaltyX    = 3.0;   % m, penalty mark (1.5 m from the goal line), drawn for reference
P.ballXRange  = [2.0 3.5];   % m, the ball starts at a random x in this range
P.ballYRange  = [-1.5 1.5];  % m, and a random y in this range
P.ballR       = 0.07;  % m, ball radius
P.friction    = 0.3;   % m/s^2, how fast the rolling ball slows down
P.strikerR    = 0.15;  % m, striker size
P.strikerV    = 0.25;  % m/s, striker walking speed (placeholder)
P.kickSpeed   = 2.0;   % m/s, ball speed straight after the kick
P.kickNoise   = 0.08;  % rad, random error in the kick direction
P.keeperV     = 0.3;   % m/s, keeper sideways speed (placeholder)
P.keeperR     = 0.25;  % m, how far the keeper can block (body plus arms)
P.keeperLineX = 4.3;   % m, keeper stands just in front of the goal line

%% Play the shots
outcomes = cell(1, nShots);
for k = 1:nShots
    outcomes{k} = playOneShot(P, watch);
end

%% Report
if watch
    fprintf('Result: %s\n', outcomes{1});
else
    showScore(outcomes);
end
end


%% ------------------------------------------------------------------
function nShots = askUser()
% Ask the user what to do and return how many shots to play
fprintf('\nStriker vs Keeper\n');
fprintf('  1  Watch one shot\n');
fprintf('  2  Run a number of shots and show the score\n');

choice = 0;
while ~isequal(choice, 1) && ~isequal(choice, 2)
    choice = input('Choose 1 or 2: ');
end

if choice == 1
    nShots = 1;
else
    nShots = 0;
    while ~(isscalar(nShots) && nShots >= 2 && nShots == round(nShots))
        nShots = input('How many shots? (2 or more): ');
    end
    fprintf('Running %d shots...\n', nShots);
end
end


%% ------------------------------------------------------------------
function showScore(outcomes)
% Print a scoreboard for a set of shots
n     = numel(outcomes);
nGoal = sum(strcmp(outcomes, 'GOAL'));
nSave = sum(strcmp(outcomes, 'SAVE'));
nMiss = sum(strcmp(outcomes, 'MISS'));
nTime = sum(strcmp(outcomes, 'TIMEOUT'));

fprintf('\n========== SCORE ==========\n');
fprintf('  Striker  %3d  -  %3d  Keeper\n', nGoal, n - nGoal);
fprintf('---------------------------\n');
fprintf('  Shots taken  %5d\n', n);
fprintf('  Goals        %5d  (%3.0f%%)\n', nGoal, 100 * nGoal / n);
fprintf('  Saves        %5d  (%3.0f%%)\n', nSave, 100 * nSave / n);
fprintf('  Misses       %5d  (%3.0f%%)\n', nMiss, 100 * nMiss / n);
if nTime > 0
    fprintf('  Timeouts     %5d  (%3.0f%%)\n', nTime, 100 * nTime / n);
end
fprintf('===========================\n');
end


%% ------------------------------------------------------------------
function outcome = playOneShot(P, watch)
% Starting positions: the ball goes somewhere random in front of the goal
ballX   = randomBetween(P.ballXRange);
ballY   = randomBetween(P.ballYRange);
ball    = struct('x', ballX, 'y', ballY, 'vx', 0, 'vy', 0);
striker = struct('x', 1.8, 'y', -0.8, 'state', 'APPROACH');
keeper  = struct('x', P.keeperLineX, 'y', 0);

% The striker picks a random spot inside the goal to aim at
aim = [P.goalX, (2 * rand - 1) * (P.goalHalfW - 0.2)];

if watch, figure(1); clf; end
outcome = '';
for t = 0:P.dt:P.maxTime
    % 1. decide and move
    [striker, ball] = strikerStep(striker, ball, aim, P);
    keeper = keeperStep(keeper, ball, P);

    % 2. ball rolls
    ball = rollBall(ball, P);

    % 3. check
    outcome = checkOutcome(ball, keeper, striker, P);

    if watch, drawScene(ball, striker, keeper, aim, t, P); end
    if ~isempty(outcome), break; end
end
if isempty(outcome), outcome = 'TIMEOUT'; end
if watch, title(sprintf('Result: %s', outcome)); end
end


%% ------------------------------------------------------------------
function v = randomBetween(range)
% A random number between range(1) and range(2)
v = range(1) + rand * (range(2) - range(1));
end


%% ------------------------------------------------------------------
function [s, ball] = strikerStep(s, ball, aim, P)
% The striker is a tiny state machine: APPROACH -> KICK -> DONE.
d = aim - [ball.x ball.y];
u = d / norm(d);                       % unit vector from the ball to the aim point

switch s.state
    case 'APPROACH'
        % Walk to a spot just behind the ball, in line with the aim point
        spot = [ball.x ball.y] - (P.strikerR + P.ballR + 0.03) * u;
        s = walkTowards(s, spot, P.strikerV, P.dt);
        if norm(spot - [s.x s.y]) < 0.02
            s.state = 'KICK';
        end

    case 'KICK'
        % Give the ball speed towards the aim point, with a small random error
        angle = atan2(u(2), u(1)) + P.kickNoise * randn;
        ball.vx = P.kickSpeed * cos(angle);
        ball.vy = P.kickSpeed * sin(angle);
        s.state = 'DONE';

    case 'DONE'
        % Stand still and watch
end
end


%% ------------------------------------------------------------------
function k = keeperStep(k, ball, P)
if ball.vx > 0.1
    % Ball is coming: predict where it crosses the keeper's line and go there
    % (simple straight-line guess that ignores friction)
    timeToLine = (P.keeperLineX - ball.x) / ball.vx;
    targetY = ball.y + ball.vy * timeToLine;
else
    % No shot yet: wait in the middle of the goal
    targetY = 0;
end
targetY = max(min(targetY, P.goalHalfW), -P.goalHalfW);   % stay in front of the goal
k = walkTowards(k, [P.keeperLineX targetY], P.keeperV, P.dt);
end


%% ------------------------------------------------------------------
function r = walkTowards(r, target, maxSpeed, dt)
% Move in a straight line towards the target, at most maxSpeed, never overshooting
d = target - [r.x r.y];
dist = norm(d);
if dist > 0
    step = min(dist, maxSpeed * dt);
    r.x = r.x + step * d(1) / dist;
    r.y = r.y + step * d(2) / dist;
end
end


%% ------------------------------------------------------------------
function ball = rollBall(ball, P)
% Slow the ball down by friction, then move it
speed = hypot(ball.vx, ball.vy);
if speed > 0
    newSpeed = max(speed - P.friction * P.dt, 0);
    ball.vx = ball.vx * newSpeed / speed;
    ball.vy = ball.vy * newSpeed / speed;
end
ball.x = ball.x + ball.vx * P.dt;
ball.y = ball.y + ball.vy * P.dt;
end


%% ------------------------------------------------------------------
function outcome = checkOutcome(ball, keeper, striker, P)
% Returns 'GOAL', 'SAVE', 'MISS' or '' (nothing yet)
outcome = '';
touchingKeeper = hypot(ball.x - keeper.x, ball.y - keeper.y) < P.keeperR + P.ballR;
overGoalLine   = ball.x - P.ballR > P.goalX;        % whole ball over the line
ballStopped    = strcmp(striker.state, 'DONE') && hypot(ball.vx, ball.vy) == 0;

if touchingKeeper
    outcome = 'SAVE';
elseif overGoalLine && abs(ball.y) < P.goalHalfW
    outcome = 'GOAL';
elseif overGoalLine || ballStopped
    outcome = 'MISS';
end
end


%% ------------------------------------------------------------------
function drawScene(ball, striker, keeper, aim, t, P)
cla; hold on; axis equal;
axis([0 5.3 -3.2 3.2]);
plot([0 P.goalX P.goalX 0 0], [-3 -3 3 3 -3], 'k');                    % half pitch
plot(P.goalX + [0 0.6 0.6 0], P.goalHalfW * [-1 -1 1 1], 'k', 'LineWidth', 2);  % goal
plot(P.penaltyX, 0, 'k+');                                              % penalty mark
plot(aim(1), aim(2), 'gx', 'MarkerSize', 10, 'LineWidth', 2);           % striker's aim
drawCircle(striker.x, striker.y, P.strikerR, [0.1 0.3 0.9]);            % striker (blue)
drawCircle(keeper.x,  keeper.y,  P.keeperR,  [0.9 0.1 0.1]);            % keeper (red)
fill(ball.x + P.ballR * cos(0:0.3:6.3), ball.y + P.ballR * sin(0:0.3:6.3), ...
     [1 0.55 0], 'EdgeColor', 'none');                                  % ball (orange)
title(sprintf('t = %.1f s   striker: %s', t, striker.state));
hold off;
drawnow;
pause(0.02);
end

function drawCircle(x, y, r, colour)
a = linspace(0, 2 * pi, 40);
plot(x + r * cos(a), y + r * sin(a), 'Color', colour, 'LineWidth', 1.5);
end
