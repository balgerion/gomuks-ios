import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HS = "http://127.0.0.1:8008"
LINK_URL = "http://localhost:8765/video.html"
CUSTOM_CSS = '@import url("https://css.gomuks.app/theme/discord-dark.css");'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
TXN = [int(time.time() * 1000)]


def call(method, path, token=None, body=None, ok=(200,)):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(HS + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with OPENER.open(req) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as err:
        payload = json.loads(err.read() or b"{}")
        if err.code in ok:
            return err.code, payload
        raise SystemExit(f"{method} {path} -> {err.code} {payload}")


def login(user, password):
    _, resp = call("POST", "/_matrix/client/v3/login", body={
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": user},
        "password": password,
        "initial_device_display_name": "seed-script",
    })
    return resp["access_token"], resp["user_id"]


def send(token, room_id, text):
    TXN[0] += 1
    call("PUT", f"/_matrix/client/v3/rooms/{urllib.parse.quote(room_id)}/send/m.room.message/{TXN[0]}", token,
         {"msgtype": "m.text", "body": text})


def send_image(token, room_id):
    import io
    from PIL import Image
    buffer = io.BytesIO()
    Image.new("RGB", (800, 600), (200, 40, 40)).save(buffer, format="PNG")
    body = buffer.getvalue()
    req = urllib.request.Request(HS + "/_matrix/media/v3/upload?filename=test.png", data=body, method="POST")
    req.add_header("Content-Type", "image/png")
    req.add_header("Authorization", "Bearer " + token)
    with OPENER.open(req) as resp:
        uri = json.loads(resp.read())["content_uri"]
    TXN[0] += 1
    call("PUT", f"/_matrix/client/v3/rooms/{urllib.parse.quote(room_id)}/send/m.room.message/{TXN[0]}", token,
         {"msgtype": "m.image", "body": "test.png", "url": uri,
          "info": {"mimetype": "image/png", "w": 800, "h": 600, "size": len(body)}})


def send_link(token, room_id, url):
    _, preview = call("GET", "/_matrix/client/v1/media/preview_url?url=" + urllib.parse.quote(url, safe=""), token)
    bundled = {"matched_url": url}
    for key in ("og:title", "og:description", "og:url", "og:image:width", "og:image:height", "og:image:type"):
        if key in preview:
            bundled[key] = preview[key]
    image = preview.get("og:image")
    if image and image.startswith("mxc://"):
        req = urllib.request.Request(HS + "/_matrix/client/v1/media/download/" + image[len("mxc://"):])
        req.add_header("Authorization", "Bearer " + token)
        with OPENER.open(req) as resp:
            data = resp.read()
            mime = resp.headers.get("Content-Type", "image/png")
        req = urllib.request.Request(HS + "/_matrix/media/v3/upload?filename=preview", data=data, method="POST")
        req.add_header("Content-Type", mime)
        req.add_header("Authorization", "Bearer " + token)
        with OPENER.open(req) as resp:
            bundled["og:image"] = json.loads(resp.read())["content_uri"]
        bundled["matrix:image:size"] = len(data)
    TXN[0] += 1
    call("PUT", f"/_matrix/client/v3/rooms/{urllib.parse.quote(room_id)}/send/m.room.message/{TXN[0]}", token,
         {"msgtype": "m.text", "body": f"watch this {url}", "com.beeper.linkpreviews": [bundled]})


def resolve(alias):
    status, resp = call("GET", "/_matrix/client/v3/directory/room/" + urllib.parse.quote(alias), ok=(200, 404))
    return resp.get("room_id") if status == 200 else None


WORDS = ("lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore "
         "et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip "
         "ex ea commodo consequat duis aute irure in reprehenderit voluptate velit esse cillum").split()


def text_for(i):
    n = [3, 8, 15, 30, 60, 5, 120, 12][i % 8]
    words = [WORDS[(i * 7 + k * 3) % len(WORDS)] for k in range(n)]
    return f"#{i:03d} " + " ".join(words)


def main():
    t_tok, t_id = login("tester", "testpass")
    f_tok, f_id = login("friend", "friendpass")
    call("PUT", f"/_matrix/client/v3/user/{urllib.parse.quote(t_id)}/account_data/fi.mau.gomuks.preferences", t_tok,
         {"custom_css": CUSTOM_CSS, "show_media_previews": True})
    if resolve("#dm:localhost"):
        print("already seeded")
        return
    if resolve("#main:localhost"):
        raise SystemExit("partial seed detected, run setup.sh --reset")
    rooms = {}
    for alias, name, direct in (("main", "Main Room", False), ("side", "Side Room", False), (None, None, True)):
        body = {"preset": "private_chat", "invite": [f_id]}
        if alias:
            body.update({"room_alias_name": alias, "name": name})
        if direct:
            body.update({"is_direct": True, "preset": "trusted_private_chat"})
        _, resp = call("POST", "/_matrix/client/v3/createRoom", t_tok, body)
        room_id = resp["room_id"]
        call("POST", f"/_matrix/client/v3/join/{urllib.parse.quote(room_id)}", f_tok, {})
        rooms[alias or "dm"] = room_id
    call("PUT", f"/_matrix/client/v3/user/{urllib.parse.quote(t_id)}/account_data/m.direct", t_tok,
         {f_id: [rooms["dm"]]})
    call("PUT", f"/_matrix/client/v3/user/{urllib.parse.quote(f_id)}/account_data/m.direct", f_tok,
         {t_id: [rooms["dm"]]})
    for i in range(150):
        send(t_tok if i % 2 == 0 else f_tok, rooms["main"], text_for(i))
        if i == 145:
            send_link(f_tok, rooms["main"], LINK_URL)
        if i in (146, 147):
            send_image(f_tok, rooms["main"])
    for i in range(10):
        send(f_tok if i % 2 == 0 else t_tok, rooms["side"], "side " + text_for(i))
    for i in range(6):
        send(f_tok if i % 2 == 0 else t_tok, rooms["dm"], "dm " + text_for(i))
    call("PUT", "/_matrix/client/v3/directory/room/%23dm%3Alocalhost", t_tok, {"room_id": rooms["dm"]})
    print(json.dumps(rooms))


if __name__ == "__main__":
    sys.exit(main())
