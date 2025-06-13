import pygame
import math
import sys
from sexpdata import loads, Symbol, Quoted

WIDTH, HEIGHT = 800, 800
FPS = 60
BULLET_COLOR = (255, 0, 0)
BULLET_RADIUS = 5

# ---------- Bullet Logic ----------


class Bullet:
    def __init__(self, uid, x, y, direction, speed):
        self.uid = uid
        self.x = x
        self.y = y
        self.dir = math.radians(direction % 360)
        self.speed = speed

    def advance(self, dt):
        self.x += self.speed * dt * math.cos(self.dir)
        self.y += self.speed * dt * math.sin(self.dir)

    def pos(self):
        return int(WIDTH / 2 + self.x), int(HEIGHT / 2 - self.y)

    def update_from_data(self, x, y, direction, speed):
        """Update bullet properties from frame data"""
        self.x = x
        self.y = y
        self.dir = math.radians(direction % 360)
        self.speed = speed


# ---------- Parser ----------


def unquote(obj):
    """Return the value inside a Quoted wrapper, or the object itself."""
    if isinstance(obj, Quoted):
        # 新版 sexpdata: .value 属性；旧版当成 list 取第 0 个
        return getattr(obj, "value", obj[0])
    return obj


def parse_bullet(sexp):
    sexp = unquote(sexp)
    assert sexp[0] == Symbol("bullet")
    data = {}
    for part in sexp[1:]:
        key = part[0].value()  # Symbol -> str
        if key == "uid":
            data["uid"] = int(part[1])
        elif key == "position":
            data["position"] = (float(part[1]), float(part[2]))
        elif key == "direction":
            data["direction"] = float(part[1])
        elif key == "speed":
            data["speed"] = float(part[1])
    return data


def parse_ftl_file(path):
    with open(path, "r") as f:
        sexpr_text = f.read()

    expr = loads(sexpr_text)
    expr = unquote(expr)  # 顶层也可能被 quote

    if expr[0] != Symbol("ftl"):
        raise ValueError("Not a valid FTL v1 structure (missing (ftl …))")

    frames = {}
    for frame_expr in expr[1:]:
        frame_expr = unquote(frame_expr)
        assert frame_expr[0] == Symbol("frame")
        frame_no = int(frame_expr[1])
        bullet_data = [parse_bullet(b) for b in frame_expr[2:]]
        frames[frame_no] = bullet_data
    return frames


# ---------- Pygame Loop ----------

OUT_MARGIN = 2 * BULLET_RADIUS  # 允许完全飞出视窗再销毁


def run_pygame(frames):
    pygame.init()
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption("Fudanmaku Renderer")
    clock = pygame.time.Clock()

    bullet_registry = {}  # uid -> Bullet object
    frame_idx = 0
    running = True

    # 让动画自然结束：最后一帧之后、场上无子弹就退出
    last_frame = max(frames.keys()) if frames else 0

    while running:
        dt = clock.tick(FPS) / (1000.0 / FPS)  # 固定步长 1
        screen.fill((0, 0, 0))

        # ① 处理新帧数据：创建新子弹或更新现有子弹
        if frame_idx in frames:
            for bullet_data in frames[frame_idx]:
                uid = bullet_data["uid"]
                pos = bullet_data["position"]
                direction = bullet_data["direction"]
                speed = bullet_data["speed"]

                if uid not in bullet_registry:
                #    print("New bullet:", uid)
                    # 新子弹：创建并加入注册表
                    bullet_registry[uid] = Bullet(uid, pos[0], pos[1], direction, speed)
                else:
                #    print(f"Update {uid}")
                    # 已存在的子弹：更新属性（用于transform等情况）
                    bullet_registry[uid].update_from_data(
                        pos[0], pos[1], direction, speed
                    )

        # ② 更新所有子弹位置并绘制，移除飞出窗口的子弹
        to_remove = []
        for uid, bullet in bullet_registry.items():
            bullet.advance(1)  # 这里 dt 固定 1 帧
            x, y = bullet.pos()

            if (
                -OUT_MARGIN <= x <= WIDTH + OUT_MARGIN
                and -OUT_MARGIN <= y <= HEIGHT + OUT_MARGIN
            ):
                pygame.draw.circle(screen, BULLET_COLOR, (x, y), BULLET_RADIUS)
            else:
                to_remove.append(uid)

        # 移除飞出窗口的子弹
        for uid in to_remove:
            del bullet_registry[uid]

        pygame.display.flip()
        frame_idx += 1

        # 自动结束：帧数播完且场上没子弹
        if frame_idx > last_frame and not bullet_registry:
            running = False

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

    pygame.quit()


# ---------- Main ----------

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <ftl-file>")
        sys.exit(1)

    frames = parse_ftl_file(sys.argv[1])
    run_pygame(frames)
